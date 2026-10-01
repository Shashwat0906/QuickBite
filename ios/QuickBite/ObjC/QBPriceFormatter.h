//
//  QBPriceFormatter.h
//  QuickBite
//
//  A small Objective-C utility, exposed to Swift through the bridging header.
//  Formats amounts stored in paise (1/100 rupee) the Indian way:
//  ₹1,23,456 (lakh grouping), dropping ".00" for whole rupees.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QBPriceFormatter : NSObject

/// "₹249", "₹1,299.50", "₹1,23,456"
+ (NSString *)stringFromPaise:(NSInteger)paise;

/// Same, with a leading minus for discounts: "−₹75"
+ (NSString *)discountStringFromPaise:(NSInteger)paise;

/// Spoken form for VoiceOver: "249 rupees 50 paise"
+ (NSString *)accessibilityStringFromPaise:(NSInteger)paise;

@end

NS_ASSUME_NONNULL_END
