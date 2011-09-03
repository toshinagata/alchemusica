//
//  NSStringAdditions.m
//
//  Created by Toshi Nagata on Sat Mar 20 2004.
//
/*
    Copyright (c) 2004-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "NSStringAdditions.h"


@implementation NSString (MyStringAddition)

- (void)drawAtPoint: (NSPoint)aPoint withAttributes: (NSDictionary *)attribute clippingRect: (NSRect)aRect
{
    NSRect rect;
    rect.origin = aPoint;
    rect.size = [self sizeWithAttributes: attribute];
    if (NSIntersectsRect(rect, aRect))
        [self drawAtPoint: aPoint withAttributes: attribute];
}

@end
