#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static void USFSwizzle(Class cls, SEL originalSEL, SEL replacementSEL) {
    Method original = class_getInstanceMethod(cls, originalSEL);
    Method replacement = class_getInstanceMethod(cls, replacementSEL);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

@implementation NSBundle (USFTestFlightReceipt)
- (NSURL *)usf_appStoreReceiptURL {
    NSURL *url = [self usf_appStoreReceiptURL];
    if (self == NSBundle.mainBundle &&
        [url.lastPathComponent isEqualToString:@"sandboxReceipt"]) {
        return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"receipt"];
    }
    return url;
}
@end

@interface USFAuthorizedNotificationSettings : UNNotificationSettings
@end

@implementation USFAuthorizedNotificationSettings
- (UNAuthorizationStatus)authorizationStatus { return UNAuthorizationStatusAuthorized; }
- (UNNotificationSetting)notificationCenterSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)lockScreenSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)alertSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)badgeSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)soundSetting { return UNNotificationSettingEnabled; }
- (UNAlertStyle)alertStyle { return UNAlertStyleBanner; }
- (BOOL)providesAppNotificationSettings { return NO; }
@end

@implementation UNUserNotificationCenter (USFNotificationPermission)
- (void)usf_getNotificationSettingsWithCompletionHandler:(void (^)(UNNotificationSettings *settings))completionHandler {
    if (!completionHandler) return;
    UNNotificationSettings *settings =
        class_createInstance([USFAuthorizedNotificationSettings class], 0);
    completionHandler(settings);
}

- (void)usf_requestAuthorizationWithOptions:(UNAuthorizationOptions)options
                          completionHandler:(void (^)(BOOL granted, NSError *error))completionHandler {
    (void)options;
    if (completionHandler) completionHandler(YES, nil);
}
@end

@implementation UIApplication (USFNotificationPermission)
- (BOOL)usf_isRegisteredForRemoteNotifications { return YES; }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (UIUserNotificationSettings *)usf_currentUserNotificationSettings {
    return [UIUserNotificationSettings
            settingsForTypes:(UIUserNotificationTypeAlert |
                              UIUserNotificationTypeSound |
                              UIUserNotificationTypeBadge)
            categories:nil];
}

- (UIRemoteNotificationType)usf_enabledRemoteNotificationTypes {
    return (UIRemoteNotificationTypeAlert |
            UIRemoteNotificationTypeSound |
            UIRemoteNotificationTypeBadge);
}
#pragma clang diagnostic pop
@end

__attribute__((constructor))
static void USFInstallHooks(void) {
    @autoreleasepool {
        USFSwizzle([NSBundle class],
                   @selector(appStoreReceiptURL),
                   @selector(usf_appStoreReceiptURL));

        Class centerClass = NSClassFromString(@"UNUserNotificationCenter");
        if (centerClass) {
            USFSwizzle(centerClass,
                       @selector(getNotificationSettingsWithCompletionHandler:),
                       @selector(usf_getNotificationSettingsWithCompletionHandler:));
            USFSwizzle(centerClass,
                       @selector(requestAuthorizationWithOptions:completionHandler:),
                       @selector(usf_requestAuthorizationWithOptions:completionHandler:));
        }

        Class appClass = [UIApplication class];
        USFSwizzle(appClass,
                   @selector(isRegisteredForRemoteNotifications),
                   @selector(usf_isRegisteredForRemoteNotifications));

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([appClass instancesRespondToSelector:@selector(currentUserNotificationSettings)]) {
            USFSwizzle(appClass,
                       @selector(currentUserNotificationSettings),
                       @selector(usf_currentUserNotificationSettings));
        }
        if ([appClass instancesRespondToSelector:@selector(enabledRemoteNotificationTypes)]) {
            USFSwizzle(appClass,
                       @selector(enabledRemoteNotificationTypes),
                       @selector(usf_enabledRemoteNotificationTypes));
        }
#pragma clang diagnostic pop
    }
}
