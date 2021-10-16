/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 * @flow strict-local
 */

import React from 'react';
import {Button, SafeAreaView, StyleSheet, View, StatusBar} from 'react-native';
import {Colors} from 'react-native/Libraries/NewAppScreen';
import {
  RTCPeerConnection,
  RTCSessionDescription,
  RTCIceCandidate,
} from 'react-native-webrtc';
import {NativeEventEmitter, NativeModules} from 'react-native';
import {io} from 'socket.io-client';

const socket = io('ws://10.0.0.191:3000');
socket.on('connect', () => {
  console.log(socket.id);
});
socket.on('connect_error', (e) => {
  console.log('CONNECT ERROR');
  console.log(e);
});

function onDataChannelCreated(channel, origin = 'neutral') {
  // console.log('onDataChannelCreated:', channel);

  // channel.onopen = function () {
  //   console.log('CHANNEL opened!!!');
  //   const data = new Uint8Array([116, 101, 115, 116, 101]);
  //   channel.send('HELLO');
  //   channel.send(data.buffer);
  // };

  channel.onopen = function () {
    console.log('CHANNEL opened!!!');
    const data1 = new Uint8Array([116, 101, 115, 116, 101]);
    const data2 = new Uint8Array([116, 101, 115, 116, 100]);
    channel.send(data1.buffer);
    setTimeout(() => channel.send(data2.buffer), 2000);
  };

  channel.onclose = function () {
    console.log('Channel closed.');
  };

  channel.onmessage = function (e) {
    console.log('MESSAGE RECEIVED BY ' + origin + ':');
    console.log(
      'time: ' + window.performance.now() + ' evt: ' + JSON.stringify(e),
    );
  };
}

const App: () => React$Node = () => {
  const initiate = async () => {
    if (socket.connected) {
      console.log('CONNECTED');
      const eventEmitter = new NativeEventEmitter(NativeModules.WebRTCModule);
      const localRTC = new RTCPeerConnection(null, eventEmitter);
      socket.on('message', async (message) => {
        if (message.type === 'answer') {
          console.log('Got answer.');
          await localRTC.setRemoteDescription(
            new RTCSessionDescription(message),
          );
        } else if (message.type === 'candidate') {
          if (!localRTC.remoteDescription) {
            return;
          }
          await localRTC.addIceCandidate(
            new RTCIceCandidate({
              candidate: message.candidate,
              sdpMLineIndex: message.label,
              sdpMid: message.id,
            }),
          );
        }
      });
      localRTC.onicecandidate = (event) => {
        console.log('icecandidate:', event.candidate);
        if (event.candidate) {
          socket.emit('message', {
            type: 'candidate',
            label: event.candidate.sdpMLineIndex,
            id: event.candidate.sdpMid,
            candidate: event.candidate.candidate,
          });
        } else {
          console.log('End of candidates.');
        }
      };
      // // localRTC.oniceconnectionstatechange = (e) => console.log(e);
      // // localRTC.addEventListener('icecandidate', (e) => console.log(e));
      console.log('IOS CHANNEL');
      onDataChannelCreated(
        localRTC.createDataChannel('file', null, eventEmitter),
        'iOS',
      );
      const offer = await localRTC.createOffer();
      await localRTC.setLocalDescription(offer);
      socket.emit('message', localRTC.localDescription);
    }
  };
  const prepareToReceive = async () => {
    if (socket.connected) {
      console.log('CONNECTED');
      const eventEmitter = new NativeEventEmitter(NativeModules.WebRTCModule);
      const localRTC = new RTCPeerConnection(null, eventEmitter);
      socket.on('message', async (message) => {
        if (message.type === 'offer') {
          console.log('Got offer. Sending answer to peer.');
          await localRTC.setRemoteDescription(
            new RTCSessionDescription(message),
          );
          const answer = await localRTC.createAnswer();
          await localRTC.setLocalDescription(answer);
          socket.emit('message', localRTC.localDescription);
        } else if (message.type === 'candidate') {
          await localRTC.addIceCandidate(
            new RTCIceCandidate({
              candidate: message.candidate,
              sdpMLineIndex: message.label,
              sdpMid: message.id,
            }),
          );
        }
      });
      localRTC.onicecandidate = (event) => {
        console.log('icecandidate:', event.candidate);
        if (event.candidate) {
          socket.emit('message', {
            type: 'candidate',
            label: event.candidate.sdpMLineIndex,
            id: event.candidate.sdpMid,
            candidate: event.candidate.candidate,
          });
        } else {
          console.log('End of candidates.');
        }
      };
      localRTC.ondatachannel = (event) => {
        console.log('ANDROID CHANNEL');
        onDataChannelCreated(event.channel, 'ANDROID');
      };
    }
  };
  return (
    <>
      <StatusBar barStyle="dark-content" />
      <SafeAreaView style={styles.body}>
        <View style={styles.footer}>
          <Button title="Start RTC" onPress={initiate} />
          <Button title="Wait RTC" onPress={prepareToReceive} />
        </View>
      </SafeAreaView>
    </>
  );
};

const styles = StyleSheet.create({
  body: {
    backgroundColor: Colors.white,
    ...StyleSheet.absoluteFill,
  },
  stream: {
    flex: 1,
  },
  footer: {
    backgroundColor: Colors.lighter,
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
  },
});

export default App;
