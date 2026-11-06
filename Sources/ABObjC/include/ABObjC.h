#import <Foundation/Foundation.h>
#import "ABLegacyUSB.h"

NS_ASSUME_NONNULL_BEGIN

/// Führt den Block aus und fängt Objective-C-Ausnahmen ab (Apples USB-Framework meldet manche Fehler
/// als Ausnahme statt als Fehlerwert). Gibt NO zurück und füllt `reason`, wenn eine Ausnahme auftrat.
BOOL ABCatchObjCException(NS_NOESCAPE void (^block)(void), NSString * _Nullable * _Nullable reason);

NS_ASSUME_NONNULL_END
