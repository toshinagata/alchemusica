//
//  ContextMenuTextFieldCell.m
//  Alchemusica
//
//  Created by Toshi Nagata on 2017/09/24.
/*
    Copyright (c) 2008-2017 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "ContextMenuTextFieldCell.h"

@implementation ContextMenuTextFieldCell

- (void)setDrawsUnderline:(BOOL)underline
{
    drawsUnderline = underline;
}

- (BOOL)drawsUnderline
{
    return drawsUnderline;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [super drawWithFrame:cellFrame inView:controlView];
    if (drawsUnderline) {
        CGFloat x1, x2, y;
        y = cellFrame.origin.y + cellFrame.size.height - 1;
        x1 = cellFrame.origin.x;
        x2 = x1 + cellFrame.size.width;
        [[NSColor grayColor] set];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x1, y) toPoint:NSMakePoint(x2, y)];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)anEvent inRect:(NSRect)cellFrame ofView:(NSView *)aView
{
	id controlView = [self controlView];
	id menu = [self menu];
    lastMenuPoint = [controlView convertPoint:[anEvent locationInWindow] fromView:nil];
	if ([controlView isKindOfClass: [NSTableView class]]) {
		id delegate = [controlView delegate];
        int row = (int)[controlView rowAtPoint:lastMenuPoint];
        if ([delegate respondsToSelector: @selector(willUseMenu:ofCell:inRow:)])
            menu = [delegate willUseMenu:menu ofCell:self inRow:row];
		[controlView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection: NO];
	}
	return menu;
}

- (IBAction)contextMenuSelected:(id)sender
{
    NSString *stringValue;
    id controlView, delegate;
    int row;
    controlView = [self controlView];
    if (![controlView isKindOfClass:[NSTableView class]])
        return;
    delegate = [controlView delegate];
    if (![delegate respondsToSelector: @selector(stringValueForMenuItem:ofCell:inRow:)])
        return;
    row = (int)[controlView rowAtPoint:lastMenuPoint];
    stringValue = [delegate stringValueForMenuItem:sender ofCell:self inRow:row];
    if (stringValue != nil) {
        int column = (int)[controlView columnAtPoint: lastMenuPoint];
        id myWindow = [controlView window];
        id fieldEditor;
        //  Start editing mode programatically, modify the text, and end editing mode.
        //  (This seems to be the most consistent way to modify a particular cell in
        //  the table view.)
        [controlView editColumn:column row:row withEvent:nil select:YES];
        fieldEditor = [myWindow fieldEditor:NO forObject:controlView];
        if (fieldEditor != nil) {
            //  shouldChangeTextInRange:replacementString: is absolutely necessary. If this
            //  call is omitted, then Cocoa binding of the table view does not work properly.
            [fieldEditor selectAll:nil];
            if ([fieldEditor shouldChangeTextInRange:[fieldEditor selectedRange] replacementString:stringValue]) {  //  Send notifications _before_ modification
                [fieldEditor setString:stringValue];    //  Change the value
                [fieldEditor didChangeText];             //  Send notifications _after_ modification
            }
            [myWindow makeFirstResponder: controlView];  //  End editing
        }
    }
}

@end
