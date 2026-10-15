#import "MenuBarVisibility.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSString *const SLVFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const SLVConfigurationClass = @"MBAssessmentModeConfiguration";
static NSString *const SLVAssertionClass = @"MBAssessmentModeAssertion";

static NSError *SLVError(NSString *reason) {
    return [NSError errorWithDomain:@"SleeveMenuBarVisibility" code:1
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

BOOL SLVMenuBarVisibilityIsAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen(SLVFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
            available = NO;
            return;
        }
        Class configuration = NSClassFromString(SLVConfigurationClass);
        Class assertion = NSClassFromString(SLVAssertionClass);
        available = configuration && assertion
            && [configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)]
            && [assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)]
            && [assertion instancesRespondToSelector:@selector(invalidate)];
    });
    return available;
}

void SLVMenuBarVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                  NSArray<NSString *> *allowedBundleIdentifiers,
                                  void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!SLVMenuBarVisibilityIsAvailable()) {
        finish(nil, SLVError(@"MenuBarClientCore is not available on this macOS"));
        return;
    }
    @try {
        // Must be NSArrays: the framework indexes into them.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(SLVConfigurationClass) alloc],
            @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(SLVAssertionClass) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, SLVError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, @selector(activateWithConfiguration:completionHandler:), configuration,
            ^(NSError *error) { finish(error ? nil : assertion, error); });
    } @catch (NSException *exception) {
        finish(nil, SLVError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void SLVMenuBarVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:@selector(invalidate)]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, @selector(invalidate));
        }
    } @catch (NSException *exception) {
        NSLog(@"Sleeve: invalidating the menu bar restriction raised %@", exception.reason);
    }
}
