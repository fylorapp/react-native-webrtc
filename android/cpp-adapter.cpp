#include <jni.h>
#include <sys/types.h>
#include "TypedArrayApi.h"
#include "pthread.h"

using namespace facebook::jsi;
using namespace expo::gl_cpp;
using namespace std;

JavaVM *java_vm;
jclass java_class;
jobject java_object;

/**
* A simple callback function that allows us to detach current JNI Environment
* when the thread
* See https://stackoverflow.com/a/30026231 for detailed explanation
*/

void DeferThreadDetach(JNIEnv *env) {
  static pthread_key_t thread_key;

  // Set up a Thread Specific Data key, and a callback that
  // will be executed when a thread is destroyed.
  // This is only done once, across all threads, and the value
  // associated with the key for any given thread will initially
  // be NULL.
  static auto run_once = [] {
      const auto err = pthread_key_create(&thread_key, [](void *ts_env) {
          if (ts_env) {
            java_vm->DetachCurrentThread();
          }
      });
      if (err) {
        // Failed to create TSD key. Throw an exception if you want to.
      }
      return 0;
  }();

  // For the callback to actually be executed when a thread exits
  // we need to associate a non-NULL value with the key on that thread.
  // We can use the JNIEnv* as that value.
  const auto ts_env = pthread_getspecific(thread_key);
  if (!ts_env) {
    if (pthread_setspecific(thread_key, env)) {
      // Failed to set thread-specific value for key. Throw an exception if you
      // want to.
    }
  }
}

/**
* Get a JNIEnv* valid for this thread, regardless of whether
* we're on a native thread or a Java thread.
* If the calling thread is not currently attached to the JVM
* it will be attached, and then automatically detached when the
* thread is destroyed.
*
* See https://stackoverflow.com/a/30026231 for detailed explanation
*/
JNIEnv *GetJniEnv() {
  JNIEnv *env = nullptr;
  // We still call GetEnv first to detect if the thread already
  // is attached. This is done to avoid setting up a DetachCurrentThread
  // call on a Java thread.

  // g_vm is a global.
  auto get_env_result = java_vm->GetEnv((void **)&env, JNI_VERSION_1_6);
  if (get_env_result == JNI_EDETACHED) {
    if (java_vm->AttachCurrentThread(&env, NULL) == JNI_OK) {
      DeferThreadDetach(env);
    } else {
      // Failed to attach thread. Throw an exception if you want to.
    }
  } else if (get_env_result == JNI_EVERSION) {
    // Unsupported JNI version. Throw an exception if you want to.
  }
  return env;
}

string jstring2string(JNIEnv *env, jstring str) {
    if (str) {
        const char *kstr = env->GetStringUTFChars(str, nullptr);
        if (kstr) {
            string result(kstr);
            env->ReleaseStringUTFChars(str, kstr);
            return result;
        }
    }
    return "";
}

jstring string2jstring(JNIEnv *env, const string &str) {
    return env->NewStringUTF(str.c_str());
}

void install(Runtime &jsiRuntime) {
    auto dataChannelSend = Function::createFromHostFunction(
            jsiRuntime, PropNameID::forAscii(jsiRuntime, "dataChannelSend"), 0,
            [](Runtime &runtime, const Value &thisValue, const Value *arguments,
               size_t count) -> Value {
                JNIEnv *jniEnv = GetJniEnv();
                java_class = jniEnv->GetObjectClass(java_object);
                jint peerConnectionId = (jint) arguments[0].getNumber();
                jstring jReactTag = string2jstring(jniEnv, arguments[1].getString(runtime).utf8(runtime));
                ArrayBuffer arrayBuffer = arguments[2].getObject(runtime).getArrayBuffer(runtime);
                size_t bufferSize = arrayBuffer.size(runtime);
                jbyte *bytes = (jbyte*) arrayBuffer.data(runtime);
                jbyteArray data = jniEnv->NewByteArray(bufferSize);
                jniEnv->SetByteArrayRegion(data, 0, bufferSize, bytes);
                jvalue args[3];
                args[0].i = peerConnectionId;
                args[1].l = jReactTag;
                args[2].l = data;
                jmethodID dataChannelSendMethod = jniEnv->GetMethodID(
                        java_class, "dataChannelSend", "(ILjava/lang/String;[B)V");
                jniEnv->CallVoidMethodA(java_object, dataChannelSendMethod, args);
                return Value(runtime, true);
    });
    auto dataChannelReceive = Function::createFromHostFunction(
            jsiRuntime, PropNameID::forAscii(jsiRuntime, "dataChannelReceive"), 0,
            [](Runtime &runtime, const Value &thisValue, const Value *arguments,
               size_t count) -> Value {
                JNIEnv *jniEnv = GetJniEnv();
                java_class = jniEnv->GetObjectClass(java_object);
                jint peerConnectionId = (jint) arguments[0].getNumber();
                jstring jReactTag = string2jstring(jniEnv, arguments[1].getString(runtime).utf8(runtime));
                jvalue args[2];
                args[0].i = peerConnectionId;
                args[1].l = jReactTag;
                jmethodID dataChannelReceiveMethod = jniEnv->GetMethodID(
                    java_class,
                    "dataChannelReceive",
                    "(ILjava/lang/String;)[B"
                );
                jbyteArray byteArray = (jbyteArray) jniEnv->CallObjectMethodA(java_object, dataChannelReceiveMethod, args);
                uint8_t *bytes = (uint8_t*) jniEnv->GetByteArrayElements(byteArray, NULL);
                TypedArray<TypedArrayKind::Uint8Array> *ta = new TypedArray<TypedArrayKind::Uint8Array>(runtime, jniEnv->GetArrayLength(byteArray));
                ta->update(runtime, bytes);
                jniEnv->DeleteLocalRef(jReactTag);
                jniEnv->DeleteLocalRef(byteArray);
                return Value(runtime, *ta);
            });
    Object *RNWebRTC = new Object(jsiRuntime);
    RNWebRTC->setProperty(jsiRuntime, "dataChannelSend", move(dataChannelSend));
    RNWebRTC->setProperty(jsiRuntime, "dataChannelReceive", move(dataChannelReceive));
    jsiRuntime.global().setProperty(jsiRuntime, "RNWebRTC", *RNWebRTC);
}

extern "C" JNIEXPORT void JNICALL
Java_com_oney_WebRTCModule_WebRTCModule_nativeInstall(JNIEnv *env,
                                                          jobject thiz,
                                                          jlong jsi) {
    auto runtime = reinterpret_cast<Runtime *>(jsi);
    if (runtime) {
        install(*runtime);
    }
    env->GetJavaVM(&java_vm);
    java_object = env->NewGlobalRef(thiz);
}
