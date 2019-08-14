// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.webviewflutter;

import android.graphics.Bitmap;
import android.annotation.TargetApi;
import android.os.Build;
import android.util.Log;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.ServiceWorkerController;
import android.webkit.ServiceWorkerClient;
import android.webkit.CookieManager;
import androidx.annotation.NonNull;
import androidx.webkit.WebViewClientCompat;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.Map;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.SequenceInputStream;


// We need to use WebViewClientCompat to get
// shouldOverrideUrlLoading(WebView view, WebResourceRequest request)
// invoked by the webview on older Android devices, without it pages that use iframes will
// be broken when a navigationDelegate is set on Android version earlier than N.
class FlutterWebViewClient {
  private static final String TAG = "FlutterWebViewClient";
  private final MethodChannel methodChannel;
  private boolean hasNavigationDelegate;

  FlutterWebViewClient(MethodChannel methodChannel) {
    this.methodChannel = methodChannel;

    ServiceWorkerController swController = ServiceWorkerController.getInstance();
    swController.setServiceWorkerClient(new ServiceWorkerClient() {
        @Override
        public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
          try {
            Map<String, String> headers = request.getRequestHeaders();
            String method = request.getMethod();
            HttpsURLConnection connection = makeURLConnection(request.getUrl().toString(), method, headers);
            if (connection.getContentType().contains("text/html")) {
              return interceptRequest(connection);
            }
          } catch(Exception e) {
          }
          return super.shouldInterceptRequest(request);
        }
    });
  }

  private HttpsURLConnection makeURLConnection(String url, String method, Map<String, String> headers) throws Exception {
    URL myURL = new URL(url);
    HttpsURLConnection connection = (HttpsURLConnection) myURL.openConnection();
    connection.setRequestMethod(method);
    connection.addRequestProperty("Cookie", CookieManager.getInstance().getCookie(myURL.getHost()));
    for (Map.Entry<String, String> entry : headers.entrySet()) {
      connection.addRequestProperty(entry.getKey(), entry.getValue());
    }

    int status = connection.getResponseCode();
    if (status == HttpsURLConnection.HTTP_MOVED_TEMP
          || status == HttpsURLConnection.HTTP_MOVED_PERM
          || status == HttpsURLConnection.HTTP_SEE_OTHER)
      return makeURLConnection(connection.getHeaderField("Location"), method, headers);
    return connection;
  }

  private WebResourceResponse interceptRequest(HttpsURLConnection connection) throws Exception {
    StringBuilder sb = new StringBuilder();
    sb.append("<script>");
    sb.append("eval(flutter_webview.getPreloadjs());");
    sb.append("</script>");
    InputStream input = new ByteArrayInputStream(sb.toString().getBytes());

    String mimeType = "text/html";
    String charset = "UTF-8";
    for (String value : connection.getContentType().split(";")) {
      value = value.trim();
      if (value.toLowerCase().startsWith("charset=")) {
        charset = value.substring("charset=".length());
      } else {
        mimeType = value;
      }
    }

    return new WebResourceResponse(mimeType, charset, new SequenceInputStream(input, connection.getInputStream()));
  }

  @TargetApi(Build.VERSION_CODES.LOLLIPOP)
  public WebResourceResponse shouldInterceptRequest (WebView view, WebResourceRequest request) {
    if (request.isForMainFrame()) {
      try {
        Map<String, String> headers = request.getRequestHeaders();
        String method = request.getMethod();
        HttpsURLConnection connection = makeURLConnection(request.getUrl().toString(), method, headers);
        return interceptRequest(connection);
      } catch(Exception e) {
      }
    }
    return null;
  }

  @TargetApi(Build.VERSION_CODES.LOLLIPOP)
  private boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
    if (!hasNavigationDelegate) {
      return false;
    }
    notifyOnNavigationRequest(
        request.getUrl().toString(), request.getRequestHeaders(), view, request.isForMainFrame());
    // We must make a synchronous decision here whether to allow the navigation or not,
    // if the Dart code has set a navigation delegate we want that delegate to decide whether
    // to navigate or not, and as we cannot get a response from the Dart delegate synchronously we
    // return true here to block the navigation, if the Dart delegate decides to allow the
    // navigation the plugin will later make an addition loadUrl call for this url.
    //
    // Since we cannot call loadUrl for a subframe, we currently only allow the delegate to stop
    // navigations that target the main frame, if the request is not for the main frame
    // we just return false to allow the navigation.
    //
    // For more details see: https://github.com/flutter/flutter/issues/25329#issuecomment-464863209
    return request.isForMainFrame();
  }

  private boolean shouldOverrideUrlLoading(WebView view, String url) {
    if (!hasNavigationDelegate) {
      return false;
    }
    // This version of shouldOverrideUrlLoading is only invoked by the webview on devices with
    // webview versions  earlier than 67(it is also invoked when hasNavigationDelegate is false).
    // On these devices we cannot tell whether the navigation is targeted to the main frame or not.
    // We proceed assuming that the navigation is targeted to the main frame. If the page had any
    // frames they will be loaded in the main frame instead.
    Log.w(
        TAG,
        "Using a navigationDelegate with an old webview implementation, pages with frames or iframes will not work");
    notifyOnNavigationRequest(url, null, view, true);
    return true;
  }

  private void onPageFinished(WebView view, String url) {
    Map<String, Object> args = new HashMap<>();
    args.put("url", url);
    methodChannel.invokeMethod("onPageFinished", args);
  }

  private void onPageStarted(WebView view, String url) {
    Map<String, Object> args = new HashMap<>();
    args.put("url", url);
    methodChannel.invokeMethod("onPageStarted", args);
  }

  private void notifyOnNavigationRequest(
      String url, Map<String, String> headers, WebView webview, boolean isMainFrame) {
    HashMap<String, Object> args = new HashMap<>();
    args.put("url", url);
    args.put("isForMainFrame", isMainFrame);
    if (isMainFrame) {
      methodChannel.invokeMethod(
          "navigationRequest", args, new OnNavigationRequestResult(url, headers, webview));
    } else {
      methodChannel.invokeMethod("navigationRequest", args);
    }
  }

  // This method attempts to avoid using WebViewClientCompat due to bug
  // https://bugs.chromium.org/p/chromium/issues/detail?id=925887. Also, see
  // https://github.com/flutter/flutter/issues/29446.
  WebViewClient createWebViewClient(boolean hasNavigationDelegate) {
    this.hasNavigationDelegate = hasNavigationDelegate;

    if (!hasNavigationDelegate || android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      return internalCreateWebViewClient();
    }

    return internalCreateWebViewClientCompat();
  }

  private WebViewClient internalCreateWebViewClient() {
    return new WebViewClient() {
      @TargetApi(Build.VERSION_CODES.N)
      @Override
      public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        return FlutterWebViewClient.this.shouldOverrideUrlLoading(view, request);
      }

      @Override
      public void onPageFinished(WebView view, String url) {
        FlutterWebViewClient.this.onPageFinished(view, url);
      }

      @Override
      public void onPageStarted(WebView view, String url, Bitmap favicon) {
        FlutterWebViewClient.this.onPageStarted(view, url);
      }

      @Override
      public WebResourceResponse shouldInterceptRequest (WebView view, WebResourceRequest request) {
        return FlutterWebViewClient.this.shouldInterceptRequest(view, request);
      }
    };
  }

  private WebViewClientCompat internalCreateWebViewClientCompat() {
    return new WebViewClientCompat() {
      @Override
      public boolean shouldOverrideUrlLoading(@NonNull WebView view, @NonNull WebResourceRequest request) {
        return FlutterWebViewClient.this.shouldOverrideUrlLoading(view, request);
      }

      @Override
      public boolean shouldOverrideUrlLoading(WebView view, String url) {
        return FlutterWebViewClient.this.shouldOverrideUrlLoading(view, url);
      }

      @Override
      public void onPageFinished(WebView view, String url) {
        FlutterWebViewClient.this.onPageFinished(view, url);
      }

      @Override
      public void onPageStarted(WebView view, String url, Bitmap favicon) {
        FlutterWebViewClient.this.onPageStarted(view, url);
      }

      @Override
      public WebResourceResponse shouldInterceptRequest (WebView view, WebResourceRequest request) {
        return FlutterWebViewClient.this.shouldInterceptRequest(view, request);
      }
    };
  }

  private static class OnNavigationRequestResult implements MethodChannel.Result {
    private final String url;
    private final Map<String, String> headers;
    private final WebView webView;

    private OnNavigationRequestResult(String url, Map<String, String> headers, WebView webView) {
      this.url = url;
      this.headers = headers;
      this.webView = webView;
    }

    @Override
    public void success(Object shouldLoad) {
      Boolean typedShouldLoad = (Boolean) shouldLoad;
      if (typedShouldLoad) {
        loadUrl();
      }
    }

    @Override
    public void error(String errorCode, String s1, Object o) {
      throw new IllegalStateException("navigationRequest calls must succeed");
    }

    @Override
    public void notImplemented() {
      throw new IllegalStateException(
          "navigationRequest must be implemented by the webview method channel");
    }

    private void loadUrl() {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        webView.loadUrl(url, headers);
      } else {
        webView.loadUrl(url);
      }
    }
  }
}
