package io.flutter.plugins.webviewflutter;

import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;

class JavaScriptChannel {
  private final MethodChannel methodChannel;
  private final Handler platformThreadHandler;
  private final InputAwareWebView webView;
  private String preloadjs;

  JavaScriptChannel(
          InputAwareWebView webView, MethodChannel methodChannel, Handler platformThreadHandler) {
    this.methodChannel = methodChannel;
    this.platformThreadHandler = platformThreadHandler;
    this.webView = webView;
  }

  private String jsChannelScript = "var _callbacks = {};" +
  "var _flutter_webview = window.flutter_webview;" +
  "var _f = (promise, postID, ...args) => {" +
      "if (_callbacks.hasOwnProperty(postID)) {" +
          "if (_callbacks[postID].hasOwnProperty(promise)) {" +
              "_callbacks[postID][promise](...args);" +
          "};" +
          "delete _callbacks[postID];" +
      "};" +
  "};" +
  "Object.defineProperty(window, 'flutter_webview_succeed', {" +
      "value: (postID, ...args) => {" +
          "_f('resolve', postID, ...args);" +
      "}," +
      "writable: false" +
  "});" +
  "Object.defineProperty(window, 'flutter_webview_fail', {" +
      "value: (postID, ...args) => {" +
          "_f('reject', postID, ...args);" +
      "}," +
      "writable: false" +
  "});" +
  "Object.defineProperty(window, 'flutter_webview_post', {" +
      "value: (handler, ...args) => {" +
          "var _postID = setTimeout(() => { });" +
          "_flutter_webview.postMessage(handler, _postID, JSON.stringify(args));" +
          "return new Promise((resolve, reject) => {" +
              "_callbacks[_postID] = {};" +
              "_callbacks[_postID]['resolve'] = resolve;" +
              "_callbacks[_postID]['reject'] = reject;" +
          "});" +
      "}," +
      "writable: false" +
  "});";

  public void setPreloadJavascript(String jscode) {
    this.preloadjs = jscode;
  }

  @SuppressWarnings("unused")
  @JavascriptInterface
  public void postMessage(final String handler, final String _postID, final String args) {
    Runnable postMessageRunnable =
        new Runnable() {
          @Override
          public void run() {
            HashMap<String, String> arguments = new HashMap<>();
            arguments.put("handler", handler);
            arguments.put("arguments", args);
            methodChannel.invokeMethod("javascriptChannelMessage", arguments, new MethodChannel.Result() {
                @Override
                public void success(Object json) {
                  webView.evaluateJavascript("window.flutter_webview_succeed(" + _postID + "," + json + ");", null);
                }

                @Override
                public void error(String s, String s1, Object o) {
                 webView.evaluateJavascript("window.flutter_webview_fail(" + _postID + ",new Error(`" + s + " " + s1 + "`));", null);
                }

                @Override
                public void notImplemented() {
                }
              }
            );
          }
        };

    if (platformThreadHandler.getLooper() == Looper.myLooper()) {
      postMessageRunnable.run();
    } else {
      platformThreadHandler.post(postMessageRunnable);
    }
  }

  @SuppressWarnings("unused")
  @JavascriptInterface
  public String getPreloadjs() {
    return "(() => {" + jsChannelScript + preloadjs + "})();";
  }
}
