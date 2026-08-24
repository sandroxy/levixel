#import "LevixelUniModule.h"
#import <LevixelUniApp/LevixelUniApp-Swift.h>

@interface LevixelUniModule ()

@property (nonatomic, copy, nullable) UniModuleKeepAliveCallback eventCallback;

@end

@implementation LevixelUniModule

UNI_EXPORT_METHOD(@selector(onEvent:))
- (void)onEvent:(UniModuleKeepAliveCallback)callback {
    self.eventCallback = callback;
    [self configureEventHandler];
    [self emitType:@"ready" payload:@{@"message": @"levixel event channel ready"}];
}

UNI_EXPORT_METHOD(@selector(open:callback:))
- (void)open:(id)options callback:(UniModuleKeepAliveCallback)callback {
    [self configureEventHandler];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[LevixelUniPresenter shared] openWithOptions:options
                                             rootView:self.uniInstance.rootView
                                       viewController:self.uniInstance.viewController
                                           completion:^(NSDictionary *result) {
            if (callback) {
                callback(result, NO);
            }
        }];
    });
}

UNI_EXPORT_METHOD(@selector(close:callback:))
- (void)close:(id)options callback:(UniModuleKeepAliveCallback)callback {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[LevixelUniPresenter shared] closeWithOptions:options completion:^(NSDictionary *result) {
            if (callback) {
                callback(result, NO);
            }
        }];
    });
}

- (void)dealloc {
    self.eventCallback = nil;
    [LevixelUniPresenter shared].eventHandler = nil;
    [[LevixelUniPresenter shared] closeImmediately];
}

- (void)configureEventHandler {
    __weak typeof(self) weakSelf = self;
    [LevixelUniPresenter shared].eventHandler = ^(NSDictionary *event) {
        __strong typeof(weakSelf) selfStrong = weakSelf;
        UniModuleKeepAliveCallback callback = selfStrong.eventCallback;
        if (callback) {
            callback(event, YES);
        }
    };
}

- (void)emitType:(NSString *)type payload:(NSDictionary *)payload {
    UniModuleKeepAliveCallback callback = self.eventCallback;
    if (!callback) {
        return;
    }
    callback(@{
        @"type": type ?: @"",
        @"payload": payload ?: @{},
        @"time": @((long long)(NSDate.date.timeIntervalSince1970 * 1000.0))
    }, YES);
}

@end
