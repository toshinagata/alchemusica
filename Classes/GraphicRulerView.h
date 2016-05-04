//
//  GraphicRulerView.h
//
/*
    Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#import "GraphicClientView.h"

@interface GraphicRulerView : NSView {
	NSView *clientView;
	NSPoint dragStartPoint, dragEndPoint;
}
- (void)releaseClientView;
- (void)setClientView: (NSView *)aView;
- (NSView *)clientView;

//  No need to override this; the view type is taken from the client view
- (int)rulerViewType;

+ (NSFont *)rulerLabelFont;
+ (void)setRulerLabelFont: (NSFont *)aFont;

@end
