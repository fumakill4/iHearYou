// iHearYou | Signature: i729
#import <Foundation/Foundation.h>
// AVAudioEngine raises Objective-C exceptions for transient invalid hardware
// formats. Swift catch alone cannot intercept these configuration failures.
BOOL IHPerformAudioOperation(void (NS_NOESCAPE ^_Nonnull operation)(void), NSError * _Nullable * _Nullable error);
