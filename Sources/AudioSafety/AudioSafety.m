// iHearYou | Signature: i729
#import "AudioSafety.h"
BOOL IHPerformAudioOperation(void (^operation)(void), NSError **error) {
    @try { operation(); return YES; }
    @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"com.i729.iHearYou.audio-configuration" code:1
            userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Audio device configuration changed."}];
        return NO;
    }
}
