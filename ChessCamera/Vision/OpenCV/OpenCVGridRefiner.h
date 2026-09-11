#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Tiny Objective-C++ seam. Swift must not import opencv2.
@interface OpenCVGridRefinerBridge : NSObject

/// Inner 7×7 `findChessboardCorners` points, row-major, or nil.
+ (nullable NSArray<NSValue *> *)innerChessboardCornersInImage:(CGImageRef)image
    NS_SWIFT_NAME(innerChessboardCorners(in:));

/// Packed Hough `(rho, theta)` pairs from Canny + HoughLines (and HoughLinesP fallback).
+ (NSArray<NSNumber *> *)houghLineParametersInImage:(CGImageRef)image
    NS_SWIFT_NAME(houghLineParameters(in:));

@end

NS_ASSUME_NONNULL_END
