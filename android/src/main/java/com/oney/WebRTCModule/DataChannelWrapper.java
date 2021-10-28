package com.oney.WebRTCModule;

import java.nio.charset.StandardCharsets;

import androidx.annotation.Nullable;
import android.util.Base64;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.WritableMap;

import org.webrtc.DataChannel;

class DataChannelWrapper implements DataChannel.Observer {

    private final String reactTag;
    private final DataChannel mDataChannel;
    private final int peerConnectionId;
    private final WebRTCModule webRTCModule;
    private boolean useRawByteArray;
    private byte[] receivedDataBuffer;

    DataChannelWrapper(
            WebRTCModule webRTCModule,
            int peerConnectionId,
            String reactTag,
            DataChannel dataChannel) {
        this.webRTCModule = webRTCModule;
        this.peerConnectionId = peerConnectionId;
        this.reactTag = reactTag;
        this.receivedDataBuffer = null;
        mDataChannel = dataChannel;
    }

    DataChannelWrapper(
      WebRTCModule webRTCModule,
      int peerConnectionId,
      String reactTag,
      DataChannel dataChannel,
      boolean useRawByteArray) {
        this(webRTCModule, peerConnectionId, reactTag, dataChannel);
        this.useRawByteArray = useRawByteArray;
    }

    public DataChannel getDataChannel() {
        return mDataChannel;
    }

    public long getBufferedAmount() { return mDataChannel.bufferedAmount(); }

    public String getReactTag() {
        return reactTag;
    }

    public byte[] getReceivedData() {
      return receivedDataBuffer;
    }

    public void receiveData(byte[] data) {
      receivedDataBuffer = data;
    }

    @Nullable
    public String dataChannelStateString(DataChannel.State dataChannelState) {
        switch (dataChannelState) {
        case CONNECTING:
            return "connecting";
        case OPEN:
            return "open";
        case CLOSING:
            return "closing";
        case CLOSED:
            return "closed";
        }
        return null;
    }

    @Override
    public void onBufferedAmountChange(long amount) {
        // TODO.
    }

    @Override
    public void onMessage(DataChannel.Buffer buffer) {
        WritableMap params = Arguments.createMap();
        params.putString("reactTag", reactTag);
        params.putInt("peerConnectionId", peerConnectionId);

        byte[] bytes;
        if (buffer.data.hasArray()) {
            bytes = buffer.data.array();
        } else {
            bytes = new byte[buffer.data.remaining()];
            buffer.data.get(bytes);
        }

        if (useRawByteArray && buffer.binary) {
          receiveData(bytes);
          webRTCModule.sendEvent("dataChannelReceiveRawMessage", params);
          return;
        }

        String type;
        String data;
        if (buffer.binary) {
            type = "binary";
            data = Base64.encodeToString(bytes, Base64.NO_WRAP);
        } else {
            type = "text";
            data = new String(bytes, StandardCharsets.UTF_8);
        }
        params.putString("type", type);
        params.putString("data", data);

        webRTCModule.sendEvent("dataChannelReceiveMessage", params);
    }

    @Override
    public void onStateChange() {
        WritableMap params = Arguments.createMap();
        params.putString("reactTag", reactTag);
        params.putInt("peerConnectionId", peerConnectionId);
        params.putInt("id", mDataChannel.id());
        params.putString("state", dataChannelStateString(mDataChannel.state()));
        webRTCModule.sendEvent("dataChannelStateChanged", params);
    }
}
