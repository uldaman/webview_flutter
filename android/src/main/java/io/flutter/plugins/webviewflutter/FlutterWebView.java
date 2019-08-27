// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.webviewflutter;

import android.annotation.TargetApi;
import android.content.Context;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.os.Handler;
import android.view.View;
import android.webkit.WebView;
import android.webkit.WebSettings;
import android.webkit.WebChromeClient;
import android.webkit.WebStorage;
import android.webkit.WebViewClient;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.platform.PlatformView;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Picture;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

public class FlutterWebView implements PlatformView, MethodCallHandler {
  private final InputAwareWebView webView;
  private final MethodChannel methodChannel;
  private final FlutterWebViewClient flutterWebViewClient;
  private final Handler platformThreadHandler;
  private String currentURL = "";

  @TargetApi(Build.VERSION_CODES.JELLY_BEAN_MR1)
  @SuppressWarnings("unchecked")
  FlutterWebView(
      final Context context,
      BinaryMessenger messenger,
      int id,
      Map<String, Object> params,
      final View containerView) {

    DisplayListenerProxy displayListenerProxy = new DisplayListenerProxy();
    DisplayManager displayManager =
        (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
    displayListenerProxy.onPreWebViewInitialization(displayManager);
    webView = new InputAwareWebView(context, containerView);
    displayListenerProxy.onPostWebViewInitialization(displayManager);

    platformThreadHandler = new Handler(context.getMainLooper());

    webView.getSettings().setDatabaseEnabled(true);
    webView.getSettings().setDomStorageEnabled(true);
    webView.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);

    methodChannel = new MethodChannel(messenger, "plugins.flutter.io/webview_" + id);
    methodChannel.setMethodCallHandler(this);

    flutterWebViewClient = new FlutterWebViewClient(methodChannel);
    applySettings((Map<String, Object>) params.get("settings"));

    JavaScriptChannel jsc = new JavaScriptChannel(webView, methodChannel, platformThreadHandler);
    if (params.containsKey("injectJavascript")) {
       jsc.setPreloadJavascript((String)params.get("injectJavascript"));
    }
    webView.addJavascriptInterface(jsc, "flutter_webview");

    updateAutoMediaPlaybackPolicy((Integer) params.get("autoMediaPlaybackPolicy"));
    if (params.containsKey("userAgent")) {
      String userAgent = (String) params.get("userAgent");
      updateUserAgent(userAgent);
    }
    if (params.containsKey("initialUrl")) {
      String url = (String) params.get("initialUrl");
      webView.loadUrl(url);
    }
  }

  @Override
  public View getView() {
    return webView;
  }

  // @Override
  // This is overriding a method that hasn't rolled into stable Flutter yet. Including the
  // annotation would cause compile time failures in versions of Flutter too old to include the new
  // method. However leaving it raw like this means that the method will be ignored in old versions
  // of Flutter but used as an override anyway wherever it's actually defined.
  // TODO(mklim): Add the @Override annotation once flutter/engine#9727 rolls to stable.
  public void onInputConnectionUnlocked() {
    webView.unlockInputConnection();
  }

  // @Override
  // This is overriding a method that hasn't rolled into stable Flutter yet. Including the
  // annotation would cause compile time failures in versions of Flutter too old to include the new
  // method. However leaving it raw like this means that the method will be ignored in old versions
  // of Flutter but used as an override anyway wherever it's actually defined.
  // TODO(mklim): Add the @Override annotation once flutter/engine#9727 rolls to stable.
  public void onInputConnectionLocked() {
    webView.lockInputConnection();
  }

  @Override
  public void onMethodCall(MethodCall methodCall, Result result) {
    switch (methodCall.method) {
      case "loadUrl":
        loadUrl(methodCall, result);
        break;
      case "updateSettings":
        updateSettings(methodCall, result);
        break;
      case "canGoBack":
        canGoBack(result);
        break;
      case "canGoForward":
        canGoForward(result);
        break;
      case "goBack":
        goBack(result);
        break;
      case "goForward":
        goForward(result);
        break;
      case "reload":
        reload(result);
        break;
      case "stopLoading":
        stopLoading(result);
        break;
      case "currentUrl":
        currentUrl(result);
        break;
      case "currentTitle":
        currentTitle(result);
        break;
      case "evaluateJavascript":
        evaluateJavaScript(methodCall, result);
        break;
      case "takeScreenshot":
        takeScreenshot(result);
        break;
      case "clearCache":
        clearCache(result);
        break;
      default:
        result.notImplemented();
    }
  }

  @SuppressWarnings("unchecked")
  private void loadUrl(MethodCall methodCall, Result result) {
    Map<String, Object> request = (Map<String, Object>) methodCall.arguments;
    String url = (String) request.get("url");
    Map<String, String> headers = (Map<String, String>) request.get("headers");
    if (headers == null) {
      headers = Collections.emptyMap();
    }
    webView.loadUrl(url, headers);
    result.success(null);
  }

  private void canGoBack(Result result) {
    result.success(webView.canGoBack());
  }

  private void canGoForward(Result result) {
    result.success(webView.canGoForward());
  }

  private void goBack(Result result) {
    if (webView.canGoBack()) {
      webView.goBack();
    }
    result.success(null);
  }

  private void goForward(Result result) {
    if (webView.canGoForward()) {
      webView.goForward();
    }
    result.success(null);
  }

  private void reload(Result result) {
    webView.reload();
    result.success(null);
  }

  private void stopLoading(Result result) {
    webView.stopLoading();
    result.success(null);
  }

  private void currentUrl(Result result) {
    result.success(webView.getUrl());
  }

  private void currentTitle(Result result) {
    result.success(webView.getTitle());
  }

  @SuppressWarnings("unchecked")
  private void updateSettings(MethodCall methodCall, Result result) {
    applySettings((Map<String, Object>) methodCall.arguments);
    result.success(null);
  }

  @TargetApi(Build.VERSION_CODES.KITKAT)
  private void evaluateJavaScript(MethodCall methodCall, final Result result) {
    String jsString = (String) methodCall.arguments;
    if (jsString == null) {
      throw new UnsupportedOperationException("JavaScript string cannot be null");
    }
    webView.evaluateJavascript(
        jsString,
        new android.webkit.ValueCallback<String>() {
          @Override
          public void onReceiveValue(String value) {
            result.success(value);
          }
        });
  }

  private void takeScreenshot(Result result) {
    Bitmap b = Bitmap.createBitmap(webView.getWidth(), webView.getHeight(), Bitmap.Config.ARGB_8888);
    Canvas c = new Canvas(b);
    webView.draw(c);
    ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
    b.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream);
    try {
      byteArrayOutputStream.close();
    } catch (IOException e) {
      e.printStackTrace();
    }
    result.success(byteArrayOutputStream.toByteArray());
  }

  private void clearCache(Result result) {
    webView.clearCache(true);
    WebStorage.getInstance().deleteAllData();
    result.success(null);
  }

  private void applySettings(Map<String, Object> settings) {
    for (String key : settings.keySet()) {
      switch (key) {
        case "jsMode":
          updateJsMode((Integer) settings.get(key));
          break;
        case "hasNavigationDelegate":
          final boolean hasNavigationDelegate = (boolean) settings.get(key);

          final WebViewClient webViewClient =
              flutterWebViewClient.createWebViewClient(hasNavigationDelegate);

          webView.setWebViewClient(webViewClient);
          webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
              Map<String, Object> args = new HashMap<>();
              if (!view.getUrl().equals(currentURL)) {
                currentURL = view.getUrl();
                args.put("url", currentURL);
                methodChannel.invokeMethod("onURLChanged", args);
              }
              args.put("progress", newProgress / 100.0);
              methodChannel.invokeMethod("onProgressChanged", args);
            }
          });
          break;
        case "debuggingEnabled":
          final boolean debuggingEnabled = (boolean) settings.get(key);
          webView.setWebContentsDebuggingEnabled(debuggingEnabled);
          break;
        case "userAgent":
          updateUserAgent((String) settings.get(key));
          break;
        default:
          throw new IllegalArgumentException("Unknown WebView setting: " + key);
      }
    }
  }

  private void updateJsMode(int mode) {
    switch (mode) {
      case 0: // disabled
        webView.getSettings().setJavaScriptEnabled(false);
        break;
      case 1: // unrestricted
        webView.getSettings().setJavaScriptEnabled(true);
        break;
      default:
        throw new IllegalArgumentException("Trying to set unknown JavaScript mode: " + mode);
    }
  }

  private void updateAutoMediaPlaybackPolicy(int mode) {
    // This is the index of the AutoMediaPlaybackPolicy enum, index 1 is always_allow, for all
    // other values we require a user gesture.
    boolean requireUserGesture = mode != 1;
    webView.getSettings().setMediaPlaybackRequiresUserGesture(requireUserGesture);
  }

  private void updateUserAgent(String userAgent) {
    webView.getSettings().setUserAgentString(userAgent);
  }

  @Override
  public void dispose() {
    methodChannel.setMethodCallHandler(null);
    webView.dispose();
    webView.destroy();
  }
}
