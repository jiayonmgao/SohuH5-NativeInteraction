//
//  SHUIWebView.m
//  SohuH5-NativeInteraction
//
//  Created by 许乾隆 on 2017/10/26.
//  Copyright © 2017年 sohu-inc. All rights reserved.
//

#import <JavaScriptCore/JavaScriptCore.h>

#import "SHUIWebView.h"
#import "SHWebViewJSBridge.h"
#import "SHWebViewJS.h"
#import "SHWeakProxy.h"

@protocol SHUIWebViewJSExport <JSExport>

JSExportAs(h5InvokeNative, - (void)h5InvokeNative:(NSString *)json);

@end

@interface SHUIWebView ()<UIWebViewDelegate,SHUIWebViewJSExport>

@property (nonatomic, weak) UIWebView *uiWebView;
@property (nonatomic, strong) JSContext *context;
@property (nonatomic, strong) SHWebViewJSBridge *jsBridge;
@property (nonatomic, strong) NSURL *currentUrl;

@end

@implementation SHUIWebView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self){
        self.backgroundColor = [UIColor clearColor];
        
        [self prepareWebView];
    }
    
    return self;
}

- (void)dealloc
{
    [self.uiWebView stopLoading];
}

- (void)prepareWebView
{
    UIWebView *webview = [[UIWebView alloc]initWithFrame:self.bounds];
    webview.delegate = self;
    webview.backgroundColor = [UIColor clearColor];
    webview.opaque = NO;
    webview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 110000)
    if (@available(iOS 11.0, *)) {
        webview.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
#endif
    
    [self addSubview:webview];
    self.uiWebView = webview;
}

- (void)h5InvokeNative:(NSString *)data
{
    NSDictionary *body = nil;
    
    if([data isKindOfClass:[NSString class]]){
        body = [NSJSONSerialization JSONObjectWithData:[data dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
        NSAssert(body, @"无法解析通信通道数据:%@",data);
    
    }else if([data isKindOfClass:[NSDictionary class]]){
        body = (NSDictionary *)data;
    }else{
        NSAssert(NO, @"通信通道数据不合法:%@",data);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _weakSelf_SH
        [self.jsBridge handleH5Message:body callBack:^(NSDictionary *body) {
            _strongSelf_SH
            [self invokeH5Handler:body];
        }];
    });
}

- (void)invokeH5Handler:(NSDictionary *)body
{
    if (!body) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingPrettyPrinted error:nil];
    NSString *psString = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    
    NSString *js = [NSString stringWithFormat:@"%@(%@)",@"window.shJSBridge.invokeH5Handler",psString];
    
    [self.uiWebView stringByEvaluatingJavaScriptFromString:js];
}

//屏蔽后端发起jsbridge://访问，避免提示错误
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self setupJSContext:webView];
    
    //注入js调用native的函数
    NSString *js = SHWebView_JS();
    [self.uiWebView stringByEvaluatingJavaScriptFromString:js];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    //处理错误
}

- (void)setupJSContext:(UIView *)webView
{
    self.context = [webView valueForKeyPath:@"documentView.webView.mainFrame.javaScriptContext"];
    // 打印异常
    self.context.exceptionHandler =
    ^(JSContext *context, JSValue *exceptionValue)
    {
        context.exception = exceptionValue;
    };
    
    /// 以 JSExport 协议关联shNativeObject的方法
    SHWeakProxy *proxy = [SHWeakProxy weakProxyWithTarget:self];
    self.context[@"shNativeObject"] = proxy;
}

- (void)loadRequest:(NSURLRequest *)request
{
    [self.uiWebView loadRequest:request];
}

- (void)loadURL:(NSURL *)url
{
    self.currentUrl = url;
    [self loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)registerMethod:(NSString *)method handler:(SHWebNativeHandler)handler
{
    [self.jsBridge registerMethod:method handler:handler];
}

- (void)callH5Method:(NSString *)method data:(NSDictionary *)ps responseCallback:(SHWebResponeCallback)responseCallback
{
    if (!ps) {
        ps = @{};
    }
    
    ///保存住该callBack；当H5回调时，调用这个callBack，实现回调
    [self.jsBridge registerCallback:method callBack:responseCallback];
    
    NSDictionary *json = @{@"method":method,@"data":ps};
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    NSString *psString = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    
    NSString *js = [NSString stringWithFormat:@"%@(%@)",@"window.shJSBridge.invokeH5Method",psString];
    
    [self.uiWebView stringByEvaluatingJavaScriptFromString:js];
}

- (SHWebViewJSBridge *)jsBridge
{
    if (!_jsBridge) {
        _jsBridge = [[SHWebViewJSBridge alloc]init];
    }
    return _jsBridge;
}

@end

