import {NativeModules, NativeEventEmitter} from 'react-native';

const { WebRTCModule } = NativeModules;

let EventEmitter;

export default function getEventEmitter() {
  if (!EventEmitter) {
    EventEmitter = new NativeEventEmitter(WebRTCModule);
  }
  return EventEmitter;
};
