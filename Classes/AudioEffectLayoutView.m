//
//  AudioEffectLayoutView.m
//  Alchemusica
//
//  Created by Toshi Nagata on 2017/10/09.
//  Copyright 2006-2017 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "AudioEffectLayoutView.h"
#import "AudioEffectPanelController.h"

@implementation AudioEffectLayoutView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)drawRect:(NSRect)rect
{
    CGFloat x;
    int i, n;
//    NSDrawWindowBackground(rect);
    if (dataSource != nil) {
        NSRect b = [self bounds];
        x = [dataSource xpos_output];
        n = [dataSource numberOfChains];
        [[NSColor blackColor] set];
        for (i = 0; i < n; i++) {
            CGFloat xx, ybase;
            if (i == 0)
                xx = x;
            else
                xx = x - 16;
            ybase = b.size.height - 20 - 25 * i;
            [NSBezierPath strokeLineFromPoint:NSMakePoint(122, ybase) toPoint:NSMakePoint(xx, ybase)];
            if (i == n - 1) {
                [NSBezierPath strokeLineFromPoint:NSMakePoint(xx, ybase - 1) toPoint:NSMakePoint(xx, b.size.height - 21)];
            }
        }
    }
}

- (void)setDataSource:(AudioEffectPanelController *)aDataSource
{
    dataSource = aDataSource;
}

@end
