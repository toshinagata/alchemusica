//
//  TrackAttributeCell.m
//
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "TrackAttributeCell.h"
#include "MDTrack.h"

@implementation TrackAttributeCell

static NSDictionary *sBlackTextAttribute = nil;
static NSDictionary *sGrayTextAttribute = nil;
static int sLastPartCode = 0;

+ (BOOL)prefersTrackingUntilMouseUp
{
    /*  Continue to track mouse when the cursor moves outside the cell  */
    return YES;
}

- (int)partForPoint:(NSPoint)point inView:(NSView *)controlView
{
    int part;
    NSRect bounds = startCellFrame;
    if (NSMouseInRect(point, bounds, [controlView isFlipped])) {
        part = (int)((point.x - bounds.origin.x) * 3 / bounds.size.width) + 1;
        if (part > 3)
            part = 3;
        else if (part < 1)
            part = 1;
    } else part = 0;
    return part;
}

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)untilMouseUp
{
    startCellFrame = cellFrame;
    return [super trackMouse: theEvent inRect: cellFrame ofView: controlView untilMouseUp: untilMouseUp];
}

- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	id obj = [self objectValue];
    int value;
    if ([obj respondsToSelector: @selector(intValue)])
        value = [obj intValue];
    else value = 0;
    partCode = 0;
    startPartCode = [self partForPoint: startPoint inView: controlView];
    if (startPartCode < 3 && (value & kMDTrackAttributeMuteBySolo))
        startPartCode = 0;
    currentPartCode = startPartCode;
    [controlView display];
//    NSLog(@"startTrackingAt:inView: partCode = %d", partCode);
    if (currentPartCode == 0) {
        sLastPartCode = 0;
        return NO;
    } else return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
    int aPart;
    if (startPartCode == 0)
        return YES;
    aPart = [self partForPoint: currentPoint inView: controlView];
    if (aPart == startPartCode)
        currentPartCode = startPartCode;
    else
        currentPartCode = 0;
//    NSLog(@"continueTracking:at:inView: aPart = %d", aPart);
    [controlView display];
    return YES;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
    if (flag)
        sLastPartCode = currentPartCode;
//    NSLog(@"stopTracking:at:inView:mouseIsUp: endPartCode = %d", endPartCode);
    currentPartCode = 0;
    [controlView setNeedsDisplay: YES];
}

+ (int)lastPartCode
{
    return sLastPartCode;
}

static void
drawString(NSString *string, NSDictionary *attr, NSRect frame)
{
    [string drawInRect: frame withAttributes: attr];
//    NSSize size = [string sizeWithAttributes: attr];
//    NSPoint pt = NSMakePoint(floor(frame.origin.x + (frame.size.width - size.width) / 2), floor(frame.origin.y + frame.size.height - 0 - size.height));
//    [string drawAtPoint: pt withAttributes: attr];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	id obj = [self objectValue];
    int value;
    NSRect frame = cellFrame;
    float x0, x1, x2, x3, y0, y1;
    NSDictionary *attr;
    if ([obj respondsToSelector: @selector(intValue)])
        value = [obj intValue];
    else value = 0;
    if (sBlackTextAttribute == nil) {
        NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        NSFont *font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];
    //    [style setAlignment: NSCenterTextAlignment];
        sBlackTextAttribute = [[NSDictionary dictionaryWithObjectsAndKeys: [NSColor blackColor], NSForegroundColorAttributeName, style, NSParagraphStyleAttributeName, font, NSFontAttributeName, nil] retain];
        sGrayTextAttribute = [[NSDictionary dictionaryWithObjectsAndKeys: [NSColor lightGrayColor], NSForegroundColorAttributeName, style, NSParagraphStyleAttributeName, font, NSFontAttributeName, nil] retain];
    }
//    printf("value=%d\n", value);
    x0 = (float)floor(frame.origin.x);
    x1 = x0 + (float)floor(frame.size.width / 3);
    x2 = x0 + (float)floor(frame.size.width * 2 / 3);
    x3 = x0 + (float)floor(frame.size.width);
    frame.size.width = x1 - x0;
    if (value & kMDTrackAttributeRecord) {
        [[NSColor redColor] set];
        NSRectFill(frame);
    }
    if (value & kMDTrackAttributeMuteBySolo)
        attr = sGrayTextAttribute;
    else attr = sBlackTextAttribute;
    drawString(@"R", attr, frame);
    frame.origin.x = x1;
    frame.size.width = x2 - x1;
    if (value & kMDTrackAttributeMute) {
        [[NSColor lightGrayColor] set];
        NSRectFill(frame);
    }
    drawString(@"M", attr, frame);
    frame.origin.x = x2;
    frame.size.width = x3 - x2;
    if (value & kMDTrackAttributeSolo) {
        [[NSColor cyanColor] set];
        NSRectFill(frame);
    }
    drawString(@"S", sBlackTextAttribute, frame);
    [[NSColor lightGrayColor] set];
//    NSFrameRect(cellFrame);
    y0 = cellFrame.origin.y;
    y1 = cellFrame.origin.y + cellFrame.size.height;
    [NSBezierPath strokeLineFromPoint: NSMakePoint(x0, y1 - 0.5f) toPoint: NSMakePoint(x3, y1 - 0.5f)];
    [NSBezierPath strokeLineFromPoint: NSMakePoint(x0, y0 + 0.5f) toPoint: NSMakePoint(x3, y0 + 0.5f)];
    [NSBezierPath strokeLineFromPoint: NSMakePoint(x0 + 0.5f, y1) toPoint: NSMakePoint(x0 + 0.5f, y0)];
    [NSBezierPath strokeLineFromPoint: NSMakePoint(x1 + 0.5f, y1) toPoint: NSMakePoint(x1 + 0.5f, y0)];
    [NSBezierPath strokeLineFromPoint: NSMakePoint(x2 + 0.5f, y1) toPoint: NSMakePoint(x2 + 0.5f, y0)];
    [NSBezierPath strokeLineFromPoint: NSMakePoint(x3 - 0.5f, y1) toPoint: NSMakePoint(x3 - 0.5f, y0)];
    if (currentPartCode > 0) {
        switch(currentPartCode) {
            case 1: frame.origin.x = x0; frame.size.width = x1 - x0; break;
            case 2: frame.origin.x = x1; frame.size.width = x2 - x1; break;
            case 3: frame.origin.x = x2; frame.size.width = x3 - x2; break;
        }
        [[NSColor lightGrayColor] set];
        NSRectFillUsingOperation(frame, NSCompositePlusDarker);
    }
}

@end
