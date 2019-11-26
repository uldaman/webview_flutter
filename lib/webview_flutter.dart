// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'platform_interface.dart';
import 'src/webview_android.dart';
import 'src/webview_cupertino.dart';

typedef void WebViewCreatedCallback(WebViewController controller);

enum JavascriptMode {
  /// JavaScript execution is disabled.
  disabled,

  /// JavaScript execution is not restricted.
  unrestricted,
}

/// Callback type for handling messages sent from Javascript running in a web view.
typedef dynamic JavascriptMessageHandler(List<dynamic> arguments);

/// Information about a navigation action that is about to be executed.
class NavigationRequest {
  NavigationRequest._({this.url, this.isForMainFrame});

  /// The URL that will be loaded if the navigation is executed.
  final String url;

  /// Whether the navigation request is to be loaded as the main frame.
  final bool isForMainFrame;

  @override
  String toString() {
    return '$runtimeType(url: $url, isForMainFrame: $isForMainFrame)';
  }
}

/// A decision on how to handle a navigation request.
enum NavigationDecision {
  /// Prevent the navigation from taking place.
  prevent,

  /// Allow the navigation to take place.
  navigate,
}

/// Decides how to handle a specific navigation request.
///
/// The returned [NavigationDecision] determines how the navigation described by
/// `navigation` should be handled.
///
/// See also: [WebView.navigationDelegate].
typedef FutureOr<NavigationDecision> NavigationDelegate(
    NavigationRequest navigation);

/// Signature for when a [WebView] has finished loading a page.
typedef void PageFinishedCallback(String url);

/// Signature for when a [WebView] has started loading a page.
typedef void PageStartedCallback(String url);

/// Signature for when a [WebView] delegate has error.
typedef void DelegateErrorCallback(String error);

/// Signature for when the current [progress] of loading a page is changed.
typedef void ProgressChangedCallback(double progress);

/// Invoked by [WebViewPlatformController] when the current url is changed.
typedef void URLChangedCallback(String url);

typedef void OnCanGoBackCallback(bool canGoBack);
typedef void OnCanGoForwardCallback(bool canGoForward);

/// Specifies possible restrictions on automatic media playback.
///
/// This is typically used in [WebView.initialMediaPlaybackPolicy].
// The method channel implementation is marshalling this enum to the value's index, so the order
// is important.
enum AutoMediaPlaybackPolicy {
  /// Starting any kind of media playback requires a user action.
  ///
  /// For example: JavaScript code cannot start playing media unless the code was executed
  /// as a result of a user action (like a touch event).
  require_user_action_for_all_media_types,

  /// Starting any kind of media playback is always allowed.
  ///
  /// For example: JavaScript code that's triggered when the page is loaded can start playing
  /// video or audio.
  always_allow,
}

final RegExp _validHandlerNames = RegExp('^[a-zA-Z_][a-zA-Z0-9_]*\$');

/// A named handler for receiving messaged from JavaScript code running inside a web view.
class JavascriptHandler {
  /// Constructs a Javascript handler.
  ///
  /// The parameters `name` and `onMessageReceived` must not be null.
  JavascriptHandler({
    @required this.name,
    @required this.onMessageReceived,
  })  : assert(name != null),
        assert(onMessageReceived != null),
        assert(_validHandlerNames.hasMatch(name));

  /// The handler's name.
  ///
  /// Passing this handler object as part of a [WebView.javascriptHandlers] adds a handler object to
  /// the Javascript window object's property named `name`.
  ///
  /// The name must start with a letter or underscore(_), followed by any combination of those
  /// characters plus digits.
  ///
  /// Note that any JavaScript existing `window` property with this name will be overriden.
  ///
  /// See also [WebView.javascriptHandlers] for more details on the handler registration mechanism.
  final String name;

  /// A callback that's invoked when a message is received through the handler.
  final JavascriptMessageHandler onMessageReceived;
}

/// A web view widget for showing html content.
class WebView extends StatefulWidget {
  /// Creates a new web view.
  ///
  /// The web view can be controlled using a `WebViewController` that is passed to the
  /// `onWebViewCreated` callback once the web view is created.
  ///
  /// The `javascriptMode` and `autoMediaPlaybackPolicy` parameters must not be null.
  const WebView({
    Key key,
    this.onWebViewCreated,
    this.prompt = '',
    this.injectJavascript,
    this.initialUrl,
    this.javascriptMode = JavascriptMode.disabled,
    this.javascriptHandlers,
    this.navigationDelegate,
    this.gestureRecognizers,
    this.onPageFinished,
    this.onPageStarted,
    this.onDelegateError,
    this.onProgressChanged,
    this.onURLChanged,
    this.onCanGoBack,
    this.onCanGoForward,
    this.debuggingEnabled = false,
    this.userAgent,
    this.initialMediaPlaybackPolicy =
        AutoMediaPlaybackPolicy.require_user_action_for_all_media_types,
  })  : assert(prompt != null),
        assert(javascriptMode != null),
        assert(initialMediaPlaybackPolicy != null),
        super(key: key);

  static WebViewPlatform _platform;

  /// Sets a custom [WebViewPlatform].
  ///
  /// This property can be set to use a custom platform implementation for WebViews.
  ///
  /// Setting `platform` doesn't affect [WebView]s that were already created.
  ///
  /// The default value is [AndroidWebView] on Android and [CupertinoWebView] on iOS.
  static set platform(WebViewPlatform platform) {
    _platform = platform;
  }

  /// The WebView platform that's used by this WebView.
  ///
  /// The default value is [AndroidWebView] on Android and [CupertinoWebView] on iOS.
  static WebViewPlatform get platform {
    if (_platform == null) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          _platform = AndroidWebView();
          break;
        case TargetPlatform.iOS:
          _platform = CupertinoWebView();
          break;
        default:
          throw UnsupportedError(
              "Trying to use the default webview implementation for $defaultTargetPlatform but there isn't a default one");
      }
    }
    return _platform;
  }

  /// If not null invoked once the web view is created.
  final WebViewCreatedCallback onWebViewCreated;

  /// Which gestures should be consumed by the web view.
  ///
  /// It is possible for other gesture recognizers to be competing with the web view on pointer
  /// events, e.g if the web view is inside a [ListView] the [ListView] will want to handle
  /// vertical drags. The web view will claim gestures that are recognized by any of the
  /// recognizers on this list.
  ///
  /// When this set is empty or null, the web view will only handle pointer events for gestures that
  /// were not claimed by any other gesture recognizer.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  final String prompt;

  /// The javascript injected at document start.
  final String injectJavascript;

  /// The initial URL to load.
  final String initialUrl;

  /// Whether Javascript execution is enabled.
  final JavascriptMode javascriptMode;

  /// The set of [JavascriptHandler]s available to JavaScript code running in the web view.
  ///
  /// For each [JavascriptHandler] in the set, a handler object is made available for the
  /// JavaScript code in a window property named [JavascriptHandler.name].
  /// The JavaScript code can then call `postMessage` on that object to send a message that will be
  /// passed to [JavascriptHandler.onMessageReceived].
  ///
  /// For example for the following JavascriptHandler:
  ///
  /// ```dart
  /// JavascriptHandler(name: 'Print', onMessageReceived: (List<dynamic> arguments) { print(arguments); });
  /// ```
  ///
  /// JavaScript code can call:
  ///
  /// ```javascript
  /// Print('Hello');
  /// ```
  ///
  /// To asynchronously invoke the message handler which will print the message to standard output.
  ///
  /// Adding a new JavaScript handler only takes affect after the next page is loaded.
  ///
  /// Set values must not be null. A [JavascriptHandler.name] cannot be the same for multiple
  /// handlers in the list.
  ///
  /// A null value is equivalent to an empty set.
  final Set<JavascriptHandler> javascriptHandlers;

  /// A delegate function that decides how to handle navigation actions.
  ///
  /// When a navigation is initiated by the WebView (e.g when a user clicks a link)
  /// this delegate is called and has to decide how to proceed with the navigation.
  ///
  /// See [NavigationDecision] for possible decisions the delegate can take.
  ///
  /// When null all navigation actions are allowed.
  ///
  /// Caveats on Android:
  ///
  ///   * Navigation actions targeted to the main frame can be intercepted,
  ///     navigation actions targeted to subframes are allowed regardless of the value
  ///     returned by this delegate.
  ///   * Setting a navigationDelegate makes the WebView treat all navigations as if they were
  ///     triggered by a user gesture, this disables some of Chromium's security mechanisms.
  ///     A navigationDelegate should only be set when loading trusted content.
  ///   * On Android WebView versions earlier than 67(most devices running at least Android L+ should have
  ///     a later version):
  ///     * When a navigationDelegate is set pages with frames are not properly handled by the
  ///       webview, and frames will be opened in the main frame.
  ///     * When a navigationDelegate is set HTTP requests do not include the HTTP referer header.
  final NavigationDelegate navigationDelegate;

  /// Invoked when a page has finished loading.
  ///
  /// This is invoked only for the main frame.
  ///
  /// When [onPageFinished] is invoked on Android, the page being rendered may
  /// not be updated yet.
  ///
  /// When invoked on iOS or Android, any Javascript code that is embedded
  /// directly in the HTML has been loaded and code injected with
  /// [WebViewController.evaluateJavascript] can assume this.
  final PageFinishedCallback onPageFinished;

  /// Invoked when a page has started loading.
  final PageStartedCallback onPageStarted;

  /// Invoked when a page has started loading.
  final DelegateErrorCallback onDelegateError;

  /// Invoked by [WebViewPlatformController] when the current [progress]
  /// (range 0-1.0) of loading a page is changed.
  final ProgressChangedCallback onProgressChanged;

  /// Invoked by [WebViewPlatformController] when the current url is changed.
  final URLChangedCallback onURLChanged;

  final OnCanGoBackCallback onCanGoBack;
  final OnCanGoForwardCallback onCanGoForward;

  /// Controls whether WebView debugging is enabled.
  ///
  /// Setting this to true enables [WebView debugging on Android](https://developers.google.com/web/tools/chrome-devtools/remote-debugging/).
  ///
  /// WebView debugging is enabled by default in dev builds on iOS.
  ///
  /// To debug WebViews on iOS:
  /// - Enable developer options (Open Safari, go to Preferences -> Advanced and make sure "Show Develop Menu in Menubar" is on.)
  /// - From the Menu-bar (of Safari) select Develop -> iPhone Simulator -> <your webview page>
  ///
  /// By default `debuggingEnabled` is false.
  final bool debuggingEnabled;

  /// The value used for the HTTP User-Agent: request header.
  ///
  /// When null the platform's webview default is used for the User-Agent header.
  ///
  /// When the [WebView] is rebuilt with a different `userAgent`, the page reloads and the request uses the new User Agent.
  ///
  /// When [WebViewController.goBack] is called after changing `userAgent` the previous `userAgent` value is used until the page is reloaded.
  ///
  /// This field is ignored on iOS versions prior to 9 as the platform does not support a custom
  /// user agent.
  ///
  /// By default `userAgent` is null.
  final String userAgent;

  /// Which restrictions apply on automatic media playback.
  ///
  /// This initial value is applied to the platform's webview upon creation. Any following
  /// changes to this parameter are ignored (as long as the state of the [WebView] is preserved).
  ///
  /// The default policy is [AutoMediaPlaybackPolicy.require_user_action_for_all_media_types].
  final AutoMediaPlaybackPolicy initialMediaPlaybackPolicy;

  @override
  State<StatefulWidget> createState() => _WebViewState();
}

class _WebViewState extends State<WebView> {
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();

  _PlatformCallbacksHandler _platformCallbacksHandler;

  @override
  Widget build(BuildContext context) {
    return WebView.platform.build(
      context: context,
      onWebViewPlatformCreated: _onWebViewPlatformCreated,
      webViewPlatformCallbacksHandler: _platformCallbacksHandler,
      gestureRecognizers: widget.gestureRecognizers,
      creationParams: _creationParamsfromWidget(widget),
    );
  }

  @override
  void initState() {
    super.initState();
    _assertJavascriptHandlerNamesAreUnique();
    _platformCallbacksHandler = _PlatformCallbacksHandler(widget);
  }

  @override
  void didUpdateWidget(WebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _assertJavascriptHandlerNamesAreUnique();
    _controller.future.then((WebViewController controller) {
      _platformCallbacksHandler._widget = widget;
      controller._updateWidget(widget);
    });
  }

  void _onWebViewPlatformCreated(WebViewPlatformController webViewPlatform) {
    final WebViewController controller =
        WebViewController._(widget, webViewPlatform, _platformCallbacksHandler);
    _controller.complete(controller);
    if (widget.onWebViewCreated != null) {
      widget.onWebViewCreated(controller);
    }
  }

  void _assertJavascriptHandlerNamesAreUnique() {
    if (widget.javascriptHandlers == null ||
        widget.javascriptHandlers.isEmpty) {
      return;
    }
    assert(_extractHandlerNames(widget.javascriptHandlers).length ==
        widget.javascriptHandlers.length);
  }
}

CreationParams _creationParamsfromWidget(WebView widget) {
  return CreationParams(
    prompt: widget.prompt,
    injectJavascript: widget.injectJavascript,
    initialUrl: widget.initialUrl,
    webSettings: _webSettingsFromWidget(widget),
    userAgent: widget.userAgent,
    autoMediaPlaybackPolicy: widget.initialMediaPlaybackPolicy,
  );
}

WebSettings _webSettingsFromWidget(WebView widget) {
  return WebSettings(
    javascriptMode: widget.javascriptMode,
    hasNavigationDelegate: widget.navigationDelegate != null,
    debuggingEnabled: widget.debuggingEnabled,
    userAgent: WebSetting<String>.of(widget.userAgent),
  );
}

// This method assumes that no fields in `currentValue` are null.
WebSettings _clearUnchangedWebSettings(
    WebSettings currentValue, WebSettings newValue) {
  assert(currentValue.javascriptMode != null);
  assert(currentValue.hasNavigationDelegate != null);
  assert(currentValue.debuggingEnabled != null);
  assert(currentValue.userAgent.isPresent);
  assert(newValue.javascriptMode != null);
  assert(newValue.hasNavigationDelegate != null);
  assert(newValue.debuggingEnabled != null);
  assert(newValue.userAgent.isPresent);

  JavascriptMode javascriptMode;
  bool hasNavigationDelegate;
  bool debuggingEnabled;
  WebSetting<String> userAgent = WebSetting<String>.absent();
  if (currentValue.javascriptMode != newValue.javascriptMode) {
    javascriptMode = newValue.javascriptMode;
  }
  if (currentValue.hasNavigationDelegate != newValue.hasNavigationDelegate) {
    hasNavigationDelegate = newValue.hasNavigationDelegate;
  }
  if (currentValue.debuggingEnabled != newValue.debuggingEnabled) {
    debuggingEnabled = newValue.debuggingEnabled;
  }
  if (currentValue.userAgent != newValue.userAgent) {
    userAgent = newValue.userAgent;
  }

  return WebSettings(
    javascriptMode: javascriptMode,
    hasNavigationDelegate: hasNavigationDelegate,
    debuggingEnabled: debuggingEnabled,
    userAgent: userAgent,
  );
}

Set<String> _extractHandlerNames(Set<JavascriptHandler> handlers) {
  final Set<String> handlerNames = handlers == null
      // TODO(iskakaushik): Remove this when collection literals makes it to stable.
      // ignore: prefer_collection_literals
      ? Set<String>()
      : handlers.map((JavascriptHandler handler) => handler.name).toSet();
  return handlerNames;
}

class _PlatformCallbacksHandler implements WebViewPlatformCallbacksHandler {
  _PlatformCallbacksHandler(this._widget) {
    _updateJavascriptHandlers(_widget.javascriptHandlers);
  }

  WebView _widget;

  // Maps a handler name to a handler.
  final Map<String, JavascriptHandler> _javascriptHandlers =
      <String, JavascriptHandler>{};

  @override
  dynamic onJavaScriptChannelMessage(String handler, List<dynamic> arguments) {
    return _javascriptHandlers[handler].onMessageReceived(arguments);
  }

  @override
  FutureOr<bool> onNavigationRequest({String url, bool isForMainFrame}) async {
    final NavigationRequest request =
        NavigationRequest._(url: url, isForMainFrame: isForMainFrame);
    final bool allowNavigation = _widget.navigationDelegate == null ||
        await _widget.navigationDelegate(request) ==
            NavigationDecision.navigate;
    return allowNavigation;
  }

  @override
  void onPageFinished(String url) {
    if (_widget.onPageFinished != null) {
      _widget.onPageFinished(url);
    }
  }

  @override
  void onPageStarted(String url) {
    if (_widget.onPageStarted != null) {
      _widget.onPageStarted(url);
    }
  }

  @override
  void onDelegateError(String url) {
    if (_widget.onDelegateError != null) {
      _widget.onDelegateError(url);
    }
  }

  @override
  void onProgressChanged(double progress) {
    if (_widget.onProgressChanged != null) {
      _widget.onProgressChanged(progress);
    }
  }

  @override
  void onURLChanged(String url) {
    if (_widget.onURLChanged != null) {
      _widget.onURLChanged(url);
    }
  }

  @override
  void onCanGoBack(bool canGoBack) {
    if (_widget.onCanGoBack != null) {
      _widget.onCanGoBack(canGoBack);
    }
  }

  @override
  void onCanGoForward(bool canGoForward) {
    if (_widget.onCanGoForward != null) {
      _widget.onCanGoForward(canGoForward);
    }
  }

  void _updateJavascriptHandlers(Set<JavascriptHandler> handlers) {
    _javascriptHandlers.clear();
    if (handlers == null) {
      return;
    }
    for (JavascriptHandler handler in handlers) {
      _javascriptHandlers[handler.name] = handler;
    }
  }
}

/// Controls a [WebView].
///
/// A [WebViewController] instance can be obtained by setting the [WebView.onWebViewCreated]
/// callback for a [WebView] widget.
class WebViewController {
  WebViewController._(
    this._widget,
    this._webViewPlatformController,
    this._platformCallbacksHandler,
  ) : assert(_webViewPlatformController != null) {
    _settings = _webSettingsFromWidget(_widget);
  }

  final WebViewPlatformController _webViewPlatformController;

  final _PlatformCallbacksHandler _platformCallbacksHandler;

  WebSettings _settings;

  WebView _widget;

  /// Loads the specified URL.
  ///
  /// If `headers` is not null and the URL is an HTTP URL, the key value paris in `headers` will
  /// be added as key value pairs of HTTP headers for the request.
  ///
  /// `url` must not be null.
  ///
  /// Throws an ArgumentError if `url` is not a valid URL string.
  Future<void> loadUrl(
    String url, {
    Map<String, String> headers,
  }) async {
    assert(url != null);
    _validateUrlString(url);
    return _webViewPlatformController.loadUrl(url, headers);
  }

  /// Accessor to the current URL that the WebView is displaying.
  ///
  /// If [WebView.initialUrl] was never specified, returns `null`.
  /// Note that this operation is asynchronous, and it is possible that the
  /// current URL changes again by the time this function returns (in other
  /// words, by the time this future completes, the WebView may be displaying a
  /// different URL).
  Future<String> currentUrl() {
    return _webViewPlatformController.currentUrl();
  }

  /// Returns the title of the currently loaded page.
  Future<String> getTitle() {
    return _webViewPlatformController.getTitle();
  }

  /// Takes a screenshot (in PNG format) of the WebView's visible viewport and returns a `Uint8List`. Returns `null` if it wasn't be able to take it.
  Future<Uint8List> takeScreenshot() {
    return _webViewPlatformController.takeScreenshot();
  }

  /// Checks whether there's a back history item.
  ///
  /// Note that this operation is asynchronous, and it is possible that the "canGoBack" state has
  /// changed by the time the future completed.
  Future<bool> canGoBack() {
    return _webViewPlatformController.canGoBack();
  }

  /// Checks whether there's a forward history item.
  ///
  /// Note that this operation is asynchronous, and it is possible that the "canGoForward" state has
  /// changed by the time the future completed.
  Future<bool> canGoForward() {
    return _webViewPlatformController.canGoForward();
  }

  /// Goes back in the history of this WebView.
  ///
  /// If there is no back history item this is a no-op.
  Future<void> goBack() {
    return _webViewPlatformController.goBack();
  }

  /// Goes forward in the history of this WebView.
  ///
  /// If there is no forward history item this is a no-op.
  Future<void> goForward() {
    return _webViewPlatformController.goForward();
  }

  /// Reloads the current URL.
  Future<void> reload() {
    return _webViewPlatformController.reload();
  }

  /// Stop loads the current URL.
  Future<void> stopLoading() {
    return _webViewPlatformController.stopLoading();
  }

  /// Clears all caches used by the [WebView].
  ///
  /// The following caches are cleared:
  ///	1. Browser HTTP Cache.
  ///	2. [Cache API](https://developers.google.com/web/fundamentals/instant-and-offline/web-storage/cache-api) caches.
  ///    These are not yet supported in iOS WkWebView. Service workers tend to use this cache.
  ///	3. Application cache.
  ///	4. Local Storage.
  ///
  /// Note: Calling this method also triggers a reload.
  Future<void> clearCache() async {
    await _webViewPlatformController.clearCache();
    return reload();
  }

  Future<void> _updateWidget(WebView widget) async {
    _widget = widget;
    await _updateSettings(_webSettingsFromWidget(widget));
    await _updateJavascriptHandlers(widget.javascriptHandlers);
  }

  Future<void> _updateSettings(WebSettings newSettings) {
    final WebSettings update =
        _clearUnchangedWebSettings(_settings, newSettings);
    _settings = newSettings;
    return _webViewPlatformController.updateSettings(update);
  }

  Future<void> _updateJavascriptHandlers(
      Set<JavascriptHandler> newHandlers) async {
    _platformCallbacksHandler._updateJavascriptHandlers(newHandlers);
  }

  /// Evaluates a JavaScript expression in the context of the current page.
  ///
  /// On Android returns the evaluation result as a JSON formatted string.
  ///
  /// On iOS depending on the value type the return value would be one of:
  ///
  ///  - For primitive JavaScript types: the value string formatted (e.g JavaScript 100 returns '100').
  ///  - For JavaScript arrays of supported types: a string formatted NSArray(e.g '(1,2,3), note that the string for NSArray is formatted and might contain newlines and extra spaces.').
  ///  - Other non-primitive types are not supported on iOS and will complete the Future with an error.
  ///
  /// The Future completes with an error if a JavaScript error occurred, or on iOS, if the type of the
  /// evaluated expression is not supported as described above.
  ///
  /// When evaluating Javascript in a [WebView], it is best practice to wait for
  /// the [WebView.onPageFinished] callback. This guarantees all the Javascript
  /// embedded in the main frame HTML has been loaded.
  Future<String> evaluateJavascript(String javascriptString) {
    if (_settings.javascriptMode == JavascriptMode.disabled) {
      return Future<String>.error(FlutterError(
          'JavaScript mode must be enabled/unrestricted when calling evaluateJavascript.'));
    }
    if (javascriptString == null) {
      return Future<String>.error(
          ArgumentError('The argument javascriptString must not be null.'));
    }
    // TODO(amirh): remove this on when the invokeMethod update makes it to stable Flutter.
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    return _webViewPlatformController.evaluateJavascript(javascriptString);
  }

  Future<String> resetUserScript(String userScriptString) {
    if (_settings.javascriptMode == JavascriptMode.disabled)
      return Future<String>.error(FlutterError(
          'JavaScript mode must be enabled/unrestricted when calling resetUserScript.'));
    if (userScriptString == null)
      return Future<String>.error(
          ArgumentError('The argument userScriptString must not be null.'));
    return _webViewPlatformController.resetUserScript(userScriptString);
  }

  Future<String> setPrompt(String promptString) => promptString == null
      ? Future<String>.error(
          ArgumentError('The argument userScriptString must not be null.'),
        )
      : _webViewPlatformController.setPrompt(promptString);

  /// Sets the main page contents and base URL.
  Future<void> loadHTMLString(String html, String url) {
    return _webViewPlatformController.loadHTMLString(html, url);
  }
}

/// Manages cookies pertaining to all [WebView]s.
class CookieManager {
  /// Creates a [CookieManager] -- returns the instance if it's already been called.
  factory CookieManager() {
    return _instance ??= CookieManager._();
  }

  CookieManager._();

  static CookieManager _instance;

  /// Clears all cookies for all [WebView] instances.
  ///
  /// This is a no op on iOS version smaller than 9.
  ///
  /// Returns true if cookies were present before clearing, else false.
  Future<bool> clearCookies() => WebView.platform.clearCookies();
}

// Throws an ArgumentError if `url` is not a valid URL string.
void _validateUrlString(String url) {
  try {
    final Uri uri = Uri.parse(url);
    if (uri.scheme.isEmpty) {
      throw ArgumentError('Missing scheme in URL string: "$url"');
    }
  } on FormatException catch (e) {
    throw ArgumentError(e);
  }
}
