#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// macOS 27's own menu bar visibility restriction, from the private
// MenuBarClientCore framework that backs exam ("assessment") mode. Given an
// allow-list, MenuBarAgent hides every other status item and reflows the bar.
//
// Discovered and first used by Hidden Bar (MIT, github.com/dwarvesf/hidden).
// Objective-C so that an exception from a changed private API is caught and
// reported instead of crashing Sleeve; every name is resolved at runtime.

/// True when the framework, both classes and every selector used resolve.
BOOL SLVMenuBarVisibilityIsAvailable(void);

/// Keeps only these system items and apps visible. `completion` runs on the
/// main queue with an assertion to hold — the restriction lasts until it is
/// invalidated or this process exits — or with an error.
void SLVMenuBarVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                  NSArray<NSString *> *allowedBundleIdentifiers,
                                  void (^completion)(id _Nullable assertion, NSError * _Nullable error));

void SLVMenuBarVisibilityInvalidate(id assertion);

NS_ASSUME_NONNULL_END
