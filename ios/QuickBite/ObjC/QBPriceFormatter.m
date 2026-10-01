//
//  QBPriceFormatter.m
//  QuickBite
//

#import "QBPriceFormatter.h"

@implementation QBPriceFormatter

/// Groups the integer part as 3 digits then pairs: 1234567 → "12,34,567".
+ (NSString *)indianGroupedString:(long long)value {
    NSString *digits = [NSString stringWithFormat:@"%lld", value];
    if (digits.length <= 3) {
        return digits;
    }
    NSString *lastThree = [digits substringFromIndex:digits.length - 3];
    NSString *rest = [digits substringToIndex:digits.length - 3];
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    while (rest.length > 2) {
        [pairs insertObject:[rest substringFromIndex:rest.length - 2] atIndex:0];
        rest = [rest substringToIndex:rest.length - 2];
    }
    if (rest.length > 0) {
        [pairs insertObject:rest atIndex:0];
    }
    [pairs addObject:lastThree];
    return [pairs componentsJoinedByString:@","];
}

+ (NSString *)stringFromPaise:(NSInteger)paise {
    BOOL negative = paise < 0;
    long long absolute = llabs((long long)paise);
    long long rupees = absolute / 100;
    long long remainder = absolute % 100;

    NSString *grouped = [self indianGroupedString:rupees];
    NSString *body = remainder == 0
        ? [NSString stringWithFormat:@"₹%@", grouped]
        : [NSString stringWithFormat:@"₹%@.%02lld", grouped, remainder];
    return negative ? [@"-" stringByAppendingString:body] : body;
}

+ (NSString *)discountStringFromPaise:(NSInteger)paise {
    return [@"−" stringByAppendingString:[self stringFromPaise:labs(paise)]];
}

+ (NSString *)accessibilityStringFromPaise:(NSInteger)paise {
    long long absolute = llabs((long long)paise);
    long long rupees = absolute / 100;
    long long remainder = absolute % 100;
    NSString *rupeeWord = rupees == 1 ? @"rupee" : @"rupees";
    if (remainder == 0) {
        return [NSString stringWithFormat:@"%lld %@", rupees, rupeeWord];
    }
    return [NSString stringWithFormat:@"%lld %@ %lld paise", rupees, rupeeWord, remainder];
}

@end
