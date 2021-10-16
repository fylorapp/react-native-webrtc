'use strict';

import { NativeEventEmitter, NativeModules } from 'react-native';
import base64 from 'base64-js';
import MessageEvent from './MessageEvent';
import RTCDataChannelEvent from './RTCDataChannelEvent';

const {WebRTCModule} = NativeModules;

type RTCDataChannelState =
  'connecting' |
  'open' |
  'closing' |
  'closed';

// const DATA_CHANNEL_EVENTS = [
//   'open',
//   'message',
//   'bufferedamountlow',
//   'closing',
//   'close',
//   'error',
// ];

export default class RTCDataChannel {
  _peerConnectionId: number;
  _reactTag: string;
  _eventEmitter: NativeEventEmitter;
  _id: number;
  _label: string;
  _maxPacketLifeTime: ?number;
  _maxRetransmits: ?number;
  _negotiated: boolean;
  _ordered: boolean;
  _protocol: string;
  _readyState: RTCDataChannelState;

  binaryType: 'arraybuffer' = 'arraybuffer'; // we only support 'arraybuffer'
  bufferedAmount: number = 0;
  bufferedAmountLowThreshold: number = 0;

  onopen: ?Function;
  onmessage: ?Function;
  onbufferedamountlow: ?Function;
  onerror: ?Function;
  onclosing: ?Function;
  onclose: ?Function;

  constructor(info, eventEmitter) {
    this._peerConnectionId = info.peerConnectionId;
    this._reactTag = info.reactTag;
    this._label = info.label;
    this._id = info.id === -1 ? null : info.id; // null until negotiated.
    this._ordered = Boolean(info.ordered);
    this._maxPacketLifeTime = info.maxPacketLifeTime;
    this._maxRetransmits = info.maxRetransmits;
    this._protocol = info.protocol || '';
    this._negotiated = Boolean(info.negotiated);
    this._readyState = info.readyState;
    this._eventEmitter = eventEmitter;
    this._registerEvents();
  }

  get label(): string {
    return this._label;
  }

  get id(): number {
    return this._id;
  }

  get ordered(): boolean {
    return this._ordered;
  }

  get maxPacketLifeTime(): number {
    return this._maxPacketLifeTime;
  }

  get maxRetransmits(): number {
    return this._maxRetransmits;
  }

  get protocol(): string {
    return this._protocol;
  }

  get negotiated(): boolean {
    return this._negotiated;
  }

  get readyState(): string {
    return this._readyState;
  }

  send(data: string | ArrayBuffer) {
    if (typeof data === 'string') {
      WebRTCModule.dataChannelSend(this._peerConnectionId, this._reactTag, data, 'text');
      return;
    }
    global.RNWebRTC.dataChannelSend(this._peerConnectionId, this._reactTag, data);
  }

  close() {
    if (this._readyState === 'closing' || this._readyState === 'closed') {
      return;
    }
    WebRTCModule.dataChannelClose(this._peerConnectionId, this._reactTag);
  }

  _unregisterEvents() {
    this._subscriptions.forEach(e => e.remove());
    this._subscriptions = [];
  }

  _registerEvents() {
    this._subscriptions = [
      this._eventEmitter.addListener('dataChannelStateChanged', ev => {
        if (ev.reactTag !== this._reactTag) {
          return;
        }
        this._readyState = ev.state;
        if (this._id === null && ev.id !== -1) {
          this._id = ev.id;
        }
        if (this._readyState === 'open') {
          this.onopen(new RTCDataChannelEvent('open', {channel: this}));
        } else if (this._readyState === 'closing') {
          this.onclosing(new RTCDataChannelEvent('closing', {channel: this}));
        } else if (this._readyState === 'closed') {
          this.onclose(new RTCDataChannelEvent('close', {channel: this}));
          this._unregisterEvents();
          WebRTCModule.dataChannelDispose(this._peerConnectionId, this._reactTag);
        }
      }),
      this._eventEmitter.addListener('dataChannelReceiveRawMessage', ev => {
        if (ev.reactTag !== this._reactTag) {
          return;
        }
        const bytes = global.RNWebRTC.dataChannelReceive(ev.peerConnectionId, ev.reactTag);
        this.onmessage(new MessageEvent('binary', {bytes}));
      }),
      this._eventEmitter.addListener('dataChannelReceiveMessage', ev => {
        if (ev.reactTag !== this._reactTag) {
          return;
        }
        let data = ev.data;
        if (ev.type === 'binary') {
          data = base64.toByteArray(ev.data).buffer;
        }
        this.onmessage(new MessageEvent(ev.type, {data}));
      }),
    ];
  }
}
