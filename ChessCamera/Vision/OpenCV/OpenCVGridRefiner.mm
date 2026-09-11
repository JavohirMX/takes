#import "OpenCVGridRefiner.h"

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

#include <cmath>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect.hpp>

namespace {

bool GrayMatFromCGImage(CGImageRef image, cv::Mat &gray) {
    if (image == nullptr) {
        return false;
    }
    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        return false;
    }

    cv::Mat rgba((int)height, (int)width, CV_8UC4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        rgba.data,
        width,
        height,
        8,
        rgba.step[0],
        space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(space);
    if (ctx == nullptr) {
        return false;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), image);
    CGContextRelease(ctx);
    cv::cvtColor(rgba, gray, cv::COLOR_RGBA2GRAY);
    return !gray.empty();
}

void AppendHoughLinesP(const cv::Mat &edges, std::vector<cv::Vec2f> &lines) {
    std::vector<cv::Vec4i> segments;
    cv::HoughLinesP(edges, segments, 1, CV_PI / 180.0, 40, 40, 8);
    lines.reserve(lines.size() + segments.size());
    for (const cv::Vec4i &seg : segments) {
        const double dx = (double)seg[2] - (double)seg[0];
        const double dy = (double)seg[3] - (double)seg[1];
        double theta = std::atan2(dx, -dy);
        if (theta < 0) {
            theta += CV_PI;
        }
        const double rho = (double)seg[0] * std::cos(theta) + (double)seg[1] * std::sin(theta);
        lines.push_back(cv::Vec2f((float)rho, (float)theta));
    }
}

}

@implementation OpenCVGridRefinerBridge

+ (nullable NSArray<NSValue *> *)innerChessboardCornersInImage:(CGImageRef)image {
    cv::Mat gray;
    if (!GrayMatFromCGImage(image, gray)) {
        return nil;
    }

    std::vector<cv::Point2f> corners;
    const bool found = cv::findChessboardCorners(
        gray,
        cv::Size(7, 7),
        corners,
        cv::CALIB_CB_ADAPTIVE_THRESH | cv::CALIB_CB_NORMALIZE_IMAGE
    );
    if (!found || corners.size() != 49) {
        return nil;
    }

    cv::cornerSubPix(
        gray,
        corners,
        cv::Size(5, 5),
        cv::Size(-1, -1),
        cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::MAX_ITER, 30, 0.01)
    );

    NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithCapacity:49];
    for (const cv::Point2f &p : corners) {
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(p.x, p.y)]];
    }
    return points;
}

+ (NSArray<NSNumber *> *)houghLineParametersInImage:(CGImageRef)image {
    cv::Mat gray;
    if (!GrayMatFromCGImage(image, gray)) {
        return @[];
    }

    cv::Mat blurred;
    cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 1.2);
    cv::Mat edges;
    cv::Canny(blurred, edges, 40, 120);

    const int threshold = std::max(40, std::min(gray.rows, gray.cols) / 8);
    std::vector<cv::Vec2f> lines;
    cv::HoughLines(edges, lines, 1, CV_PI / 180.0, threshold);
    if (lines.size() < 12) {
        AppendHoughLinesP(edges, lines);
    }
    if (lines.empty()) {
        return @[];
    }

    NSMutableArray<NSNumber *> *packed = [NSMutableArray arrayWithCapacity:lines.size() * 2];
    for (const cv::Vec2f &line : lines) {
        [packed addObject:@(line[0])];
        [packed addObject:@(line[1])];
    }
    return packed;
}

@end
