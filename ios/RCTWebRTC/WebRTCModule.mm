//
//  WebRTCModule.m
//
//  Created by one on 2015/9/24.
//  Copyright © 2015 One. All rights reserved.
//

#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#endif

#import <React/RCTBridge+Private.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTUtils.h>

#import <WebRTC/RTCDefaultVideoDecoderFactory.h>
#import <WebRTC/RTCDefaultVideoEncoderFactory.h>

#import "YeetJSIUtils.h"

#ifdef __cplusplus
#import "TypedArrayApi.h"
#endif

#import "WebRTCModule.h"
#import "WebRTCModule+RTCPeerConnection.h"

@interface WebRTCModule ()
@end

@implementation WebRTCModule

+ (BOOL) requiresMainQueueSetup {
    return YES;
}

- (void)dealloc
{
  [_localTracks removeAllObjects];
  _localTracks = nil;
  [_localStreams removeAllObjects];
  _localStreams = nil;

  for (NSNumber *peerConnectionId in _peerConnections) {
    RTCPeerConnection *peerConnection = _peerConnections[peerConnectionId];
    peerConnection.delegate = nil;
    [peerConnection close];
  }
  [_peerConnections removeAllObjects];

  _peerConnectionFactory = nil;
}

- (instancetype)init
{
    return [self initWithEncoderFactory:nil decoderFactory:nil];
}

- (instancetype)initWithEncoderFactory:(nullable id<RTCVideoEncoderFactory>)encoderFactory
                        decoderFactory:(nullable id<RTCVideoDecoderFactory>)decoderFactory
{
  self = [super init];
  if (self) {
    if (encoderFactory == nil) {
      encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
    }
    if (decoderFactory == nil) {
      decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
    }
    _peerConnectionFactory
      = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory
                                                  decoderFactory:decoderFactory];

    _peerConnections = [NSMutableDictionary new];
    _localStreams = [NSMutableDictionary new];
    _localTracks = [NSMutableDictionary new];

    dispatch_queue_attr_t attributes =
    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                            QOS_CLASS_USER_INITIATED, -1);
    _workerQueue = dispatch_queue_create("WebRTCModule.queue", attributes);
    [self installLibrary];
  }
  return self;
}

- (RTCMediaStream*)streamForReactTag:(NSString*)reactTag
{
  RTCMediaStream *stream = _localStreams[reactTag];
  if (!stream) {
    for (NSNumber *peerConnectionId in _peerConnections) {
      RTCPeerConnection *peerConnection = _peerConnections[peerConnectionId];
      stream = peerConnection.remoteStreams[reactTag];
      if (stream) {
        break;
      }
    }
  }
  return stream;
}

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue
{
  return _workerQueue;
}

- (NSArray<NSString *> *)supportedEvents {
  return @[
    kEventPeerConnectionSignalingStateChanged,
    kEventPeerConnectionStateChanged,
    kEventPeerConnectionAddedStream,
    kEventPeerConnectionRemovedStream,
    kEventPeerConnectionOnRenegotiationNeeded,
    kEventPeerConnectionIceConnectionChanged,
    kEventPeerConnectionIceGatheringChanged,
    kEventPeerConnectionGotICECandidate,
    kEventPeerConnectionDidOpenDataChannel,
    kEventDataChannelStateChanged,
    kEventDataChannelReceiveMessage,
    kEventDataChannelReceiveRawMessage,
    kEventMediaStreamTrackMuteChanged
  ];
}

using namespace std;
using namespace facebook::jsi;
using namespace expo::gl_cpp;

- (void)installLibrary {
    RCTCxxBridge *cxxBridge = (RCTCxxBridge *)self.bridge;
    if (!cxxBridge.runtime) {
        /**
         * This is a workaround to install library
         * as soon as runtime becomes available and is
         * not recommended. If you see random crashes in iOS
         * global.xxx not found etc. use this.
         */

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.001 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            /**
             When refreshing the app while debugging, the setBridge
             method is called too soon. The runtime is not ready yet
             quite often. We need to install library as soon as runtime
             becomes available.
             */
            [self installLibrary];
        });
        return;
    }
    install(*(Runtime *)cxxBridge.runtime, self);
}

static void install(Runtime &jsiRuntime, WebRTCModule *webRTCModule) {
    auto dataChannelSend = Function::createFromHostFunction(
            jsiRuntime, PropNameID::forAscii(jsiRuntime, "dataChannelSend"), 0,
            [webRTCModule](Runtime &runtime, const Value &thisValue, const Value *arguments,
               size_t count) -> Value {
                   NSNumber *peerConnectionId = [NSNumber numberWithInt:(int) arguments[0].getNumber()];
                   NSString *reactTag = convertJSIStringToNSString(runtime, arguments[1].getString(runtime));
                   ArrayBuffer arrayBuffer = arguments[2].getObject(runtime).getArrayBuffer(runtime);
                   size_t bufferSize = arrayBuffer.size(runtime);
                   uint8_t *bytes = arrayBuffer.data(runtime);
                   [webRTCModule dataChannelSend:peerConnectionId reactTag:reactTag data:bytes size:bufferSize];
                   return Value(runtime, true);
    });
    auto dataChannelReceive = Function::createFromHostFunction(
            jsiRuntime, PropNameID::forAscii(jsiRuntime, "dataChannelSend"), 0,
            [webRTCModule](Runtime &runtime, const Value &thisValue, const Value *arguments,
               size_t count) -> Value {
                   NSNumber *peerConnectionId = [NSNumber numberWithInt:(int) arguments[0].getNumber()];
                   NSString *reactTag = convertJSIStringToNSString(runtime, arguments[1].getString(runtime));
                   uint8_t* bytes = nil;
                   size_t bufferSize = [webRTCModule dataChannelReceive:peerConnectionId reactTag:reactTag inBuffer:&bytes];
                   if (bufferSize == 0) {
                       return Value(runtime, false);
                   }
                   TypedArray<TypedArrayKind::Uint8Array> *ta = new TypedArray<TypedArrayKind::Uint8Array>(runtime, bufferSize);
                   ta->update(runtime, bytes);
                   return Value(runtime, *ta);
    });
    Object *RNWebRTC = new Object(jsiRuntime);
    RNWebRTC->setProperty(jsiRuntime, "dataChannelSend", move(dataChannelSend));
    RNWebRTC->setProperty(jsiRuntime, "dataChannelReceive", move(dataChannelReceive));
    jsiRuntime.global().setProperty(jsiRuntime, "RNWebRTC", *RNWebRTC);
}

@end
