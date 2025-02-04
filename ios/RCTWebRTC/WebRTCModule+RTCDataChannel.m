#import <objc/runtime.h>

#import <React/RCTBridge.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTEventDispatcher.h>

#import "WebRTCModule+RTCDataChannel.h"
#import "WebRTCModule+RTCPeerConnection.h"
#import <WebRTC/RTCDataChannelConfiguration.h>


@implementation WebRTCModule (RTCDataChannel)

/*
 * Thuis methos is implemented synchronously since we need to create the DataChannel on the spot
 * and where is no good way to report an error at creation time.
 */
RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(createDataChannel:(nonnull NSNumber *)peerConnectionId
                                                   label:(NSString *)label
                                                  config:(RTCDataChannelConfiguration *)config)
{
    __block id channelInfo;

    dispatch_sync(self.workerQueue, ^{
        RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];

        if (peerConnection == nil) {
            RCTLogWarn(@"PeerConnection %@ not found", peerConnectionId);
            channelInfo = nil;
            return;
        }

        RTCDataChannel *dataChannel = [peerConnection dataChannelForLabel:label configuration:config];

        if (dataChannel == nil) {
            channelInfo = nil;
            return;
        }


        NSString *reactTag = [[NSUUID UUID] UUIDString];
        DataChannelWrapper *dcw = [[DataChannelWrapper alloc] initWithChannel:dataChannel reactTag:reactTag];
        dcw.pcId = peerConnectionId;
        peerConnection.dataChannels[reactTag] = dcw;
        dcw.delegate = self;

        channelInfo = @{
            @"peerConnectionId": peerConnectionId,
            @"reactTag": reactTag,
            @"label": dataChannel.label,
            @"id": @(dataChannel.channelId),
            @"ordered": @(dataChannel.isOrdered),
            @"maxPacketLifeTime": @(dataChannel.maxPacketLifeTime),
            @"maxRetransmits": @(dataChannel.maxRetransmits),
            @"bufferedAmount": @(dataChannel.bufferedAmount),
            @"protocol": dataChannel.protocol,
            @"negotiated": @(dataChannel.isNegotiated),
            @"readyState": [self stringForDataChannelState:dataChannel.readyState]
        };
    });

    return channelInfo;
}

RCT_EXPORT_METHOD(dataChannelClose:(nonnull NSNumber *)peerConnectionId
                     reactTag:(nonnull NSString *)tag
{
    RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];
    DataChannelWrapper *dcw = peerConnection.dataChannels[tag];
    if (dcw) {
        if (dcw.receivedBytes != nil) {
            free(dcw.receivedBytes);
        }
        [dcw.channel close];
    }
})

RCT_EXPORT_METHOD(dataChannelDispose:(nonnull NSNumber *)peerConnectionId
                            reactTag:(nonnull NSString *)tag
{
    RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];
    DataChannelWrapper *dcw = peerConnection.dataChannels[tag];
    if (dcw) {
        dcw.delegate = nil;
        if (dcw.receivedBytes != nil) {
            free(dcw.receivedBytes);
        }
        [peerConnection.dataChannels removeObjectForKey:tag];
    }
})

RCT_EXPORT_METHOD(dataChannelSend:(nonnull NSNumber *)peerConnectionId
                         reactTag:(nonnull NSString *)tag
                             data:(NSString *)data
                             type:(NSString *)type
{
    RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];
    DataChannelWrapper *dcw = peerConnection.dataChannels[tag];
    if (dcw) {
        BOOL isBinary = [type isEqualToString:@"binary"];
        NSData *bytes = isBinary ? [[NSData alloc] initWithBase64EncodedString:data options:0] : [data dataUsingEncoding:NSUTF8StringEncoding];
        RTCDataBuffer *buffer = [[RTCDataBuffer alloc] initWithData:bytes isBinary:isBinary];
        [dcw.channel sendData:buffer];
    }
})

- (void) dataChannelSend:(nonnull NSNumber *)peerConnectionId reactTag:(nonnull NSString *)tag data:(uint8_t*)data size:(size_t)size {
    RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];
    DataChannelWrapper *dcw = peerConnection.dataChannels[tag];
    NSData *bytes = [NSData dataWithBytes:data length:size];
    RTCDataBuffer *buffer = [[RTCDataBuffer alloc] initWithData:bytes isBinary:YES];
    [dcw.channel sendData:buffer];
}

- (size_t) dataChannelReceive:(nonnull NSNumber *)peerConnectionId reactTag:(nonnull NSString *)tag inBuffer:(uint8_t**)buffer {
    RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];
    DataChannelWrapper *dcw = peerConnection.dataChannels[tag];
    if (!dcw || dcw == nil) {
        return 0;
    }
    *buffer = dcw.receivedBytes;
    return dcw.bufferSize;
}

- (long) dataChannelGetBufferedAmount:(nonnull NSNumber*)pcId forReactTag:(nonnull NSString *)tag {
    RTCPeerConnection *peerConnection = self.peerConnections[pcId];
    DataChannelWrapper *dcw = peerConnection.dataChannels[tag];
    return dcw.channel.bufferedAmount;
}

- (NSString *)stringForDataChannelState:(RTCDataChannelState)state
{
  switch (state) {
    case RTCDataChannelStateConnecting: return @"connecting";
    case RTCDataChannelStateOpen: return @"open";
    case RTCDataChannelStateClosing: return @"closing";
    case RTCDataChannelStateClosed: return @"closed";
  }
  return nil;
}

#pragma mark - DataChannelWrapperDelegate methods

// Called when the data channel state has changed.
- (void)dataChannelDidChangeState:(DataChannelWrapper *)dcw
{
    RTCDataChannel *channel = dcw.channel;
    NSDictionary *event = @{@"reactTag": dcw.reactTag,
                            @"peerConnectionId": dcw.pcId,
                            @"id": @(channel.channelId),
                            @"state": [self stringForDataChannelState:channel.readyState]};
    [self sendEventWithName:kEventDataChannelStateChanged body:event];
}

// Called when a data buffer was successfully received.
- (void)dataChannel:(DataChannelWrapper *)dcw didReceiveMessageWithBuffer:(RTCDataBuffer *)buffer
{
    if (buffer.isBinary && dcw.useRawDataChannel) {
        @autoreleasepool {
            size_t bufferSize = [[buffer data] length];
            dcw.bufferSize = bufferSize;
            if (dcw.receivedBytes != nil) {
                free(dcw.receivedBytes);
            }
            dcw.receivedBytes = malloc(bufferSize);
            [[buffer data] getBytes:dcw.receivedBytes length:bufferSize];
            NSDictionary *event = @{@"reactTag": dcw.reactTag, @"peerConnectionId": dcw.pcId, @"type": @"binary"};
            [self sendEventWithName:kEventDataChannelReceiveRawMessage body:event];
            return;
        }
    }
    NSString *type;
    NSString *data;
    if (buffer.isBinary) {
    type = @"binary";
    data = [buffer.data base64EncodedStringWithOptions:0];
    } else {
    type = @"text";
    // XXX NSData has a length property which means that, when it represents
    // text, the value of its bytes property does not have to be terminated by
    // null. In such a case, NSString's stringFromUTF8String may fail and return
    // nil (which would crash the process when inserting data into NSDictionary
    // without the nil protection implemented below).
    data = [[NSString alloc] initWithData:buffer.data
                                 encoding:NSUTF8StringEncoding];
    }
    NSDictionary *event = @{@"reactTag": dcw.reactTag,
                          @"peerConnectionId": dcw.pcId,
                          @"type": type,
                          // XXX NSDictionary will crash the process upon
                          // attempting to insert nil. Such behavior is
                          // unacceptable given that protection in such a
                          // scenario is extremely simple.
                          @"data": (data ? data : [NSNull null])};
    [self sendEventWithName:kEventDataChannelReceiveMessage body:event];
}

@end
