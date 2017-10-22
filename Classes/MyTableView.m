//
//  MyTableView.m
//
//  Created by Toshi Nagata.
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

#import "MyTableView.h"
#import "ListWindowController.h"

@implementation MyTableView

- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self) {
		underlineRow = -1;
	}
	return self;
}

- (void)awakeFromNib
{
	underlineRow = -1;
}

- (void)editColumn:(NSInteger)columnIndex row:(NSInteger)rowIndex withEvent:(NSEvent *)theEvent select:(BOOL)flag
{
	//  If the delegate implements special editing feature, call it.
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(myTableView:shouldEditColumn:row:)]) {
		if (![(MyTableView *)delegate myTableView:self shouldEditColumn:(int)columnIndex row:(int)rowIndex])
			return;
	}
	//  If it does not, then do the usual thing
	[super editColumn:columnIndex row:rowIndex withEvent:theEvent select:flag];
}

- (void)textDidBeginEditing: (NSNotification *)aNotification
{
	//  Make a copy of the original string
	[originalString release];
	originalString = [[NSString allocWithZone: [self zone]] initWithString: [[aNotification object] string]];
	escapeFlag = NO;
}

- (BOOL)textShouldEndEditing: (NSText *)textObject
{
	if (escapeFlag)
		//  Restore the original string
		[textObject setString: originalString];
	return [super textShouldEndEditing: textObject];
}

/*  Keyboard navigation during editing.
 *  Return: insert a new event in the next line, and continue editing.
 *  Enter: exit editing.
 *  Escape: discard the change in the current cell and exit editing.
 *  Tab/Backtab, arrows, home, end, pageup, pagedown: move the editing cell.
 */
- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
	int column, row, newRow, oldRow, dColumn, dRow, numRows, pageRows, n;
	NSRect visibleRect;
    BOOL endEditing = NO;
    BOOL insertNewline = NO;
    BOOL pageScroll = NO;
	NSEvent *theEvent = [[self window] currentEvent];
//	unichar charCode;
//	charCode = [[theEvent charactersIgnoringModifiers] characterAtIndex: 0];
	column = (int)[self editedColumn];
	row = (int)[self editedRow];
	dColumn = dRow = 0;
	numRows = (int)[self numberOfRows];
	visibleRect = [self visibleRect];
	pageRows = (int)([self rowsInRect: visibleRect]).length - 1;
    if (aSelector == @selector(insertNewline:)) {
        if ([[theEvent charactersIgnoringModifiers] characterAtIndex: 0] == NSEnterCharacter) {
            endEditing = YES;
        } else if ([theEvent modifierFlags] & NSShiftKeyMask) {
			dRow = -1;
		} else {
			dRow = 1;
        }
    } else if (aSelector == @selector(insertTab:)) {
        dColumn = 1;
    } else if (aSelector == @selector(insertBacktab:)) {
        dColumn = -1;
/*    } else if (aSelector == @selector(moveLeft:)) {
        dColumn = -1;
    } else if (aSelector == @selector(moveRight:)) {
        dColumn = 1;
    } else if (aSelector == @selector(moveUp:)) {
        dRow = -1;
    } else if (aSelector == @selector(moveDown:)) {
        dRow = 1; */
    } else if (aSelector == @selector(scrollToBeginningOfDocument:)) {
        dRow = -(numRows - 1);
    } else if (aSelector == @selector(scrollToEndOfDocument:)) {
        dRow = (numRows - 1);
    } else if (aSelector == @selector(scrollPageUp:)) {
        dRow = -pageRows;
        pageScroll = YES;
    } else if (aSelector == @selector(scrollPageDown:)) {
        dRow = pageRows;
        pageScroll = YES;
    } else if (aSelector == @selector(cancel:)) {
		[aTextView setString: originalString];
        endEditing = YES;
    } else {
    //    NSLog(@"selector = %@", NSStringFromSelector(aSelector));
        return NO;
    }

	/*  End edit of the current cell  */
	if (![[self window] makeFirstResponder: self]) {
		/*  Cannot end edit (the value is not valid)  */
		NSBeep();
		return YES;
	}
	
	if (endEditing)
		return YES;

	/*  Continue edit  */
	newRow = (int)[self selectedRow];	/*  May have changed during confirmation  */
	oldRow = row;

	/*  Adjust the column position  */
	column += dColumn;
    n = (int)[self numberOfColumns] - 1;
	if (column > n) {
		column = 0;
		dRow = 1;
	}
	if (column < 0) {
		column = n;
		dRow = -1;
	}

	/*  Adjust the row position  */
	if (dRow != 0) {
		row += dRow;
		if (oldRow < newRow && (oldRow < row && row <= newRow))
			row--;
		else if (oldRow > newRow && (oldRow > row && row >= newRow))
			row++;
	} else {
		row = newRow;
	}
	if (row < 0)
		row = 0;
	else if (row >= (n = (int)[[self dataSource] numberOfRowsInTableView: self]))
		row = n - 1;

	if (pageScroll) {
		NSClipView *clipView = (NSClipView *)[self superview];
		NSPoint newOrigin = [clipView bounds].origin;
		float amount = [self rectOfRow: row].origin.y - [self rectOfRow: [self selectedRow]].origin.y;
	//	NSLog(@"clipView = %@, origin = (%g, %g) amount = %g", clipView, newOrigin.x, newOrigin.y, amount);
		newOrigin.y += amount;
		[clipView scrollToPoint: [clipView constrainScrollPoint: newOrigin]];
	}
	
	if (insertNewline) {
		/*  Insert an empty event with the same tick (TODO: or advance the tick by some specified value?)  */
		int32_t position = [(ListWindowController *)[self dataSource] eventPositionForTableRow: row];
		[(ListWindowController *)[self dataSource] startEditAtColumn: column creatingEventWithTick: kMDNegativeTick atPosition: position + 1];
	} else {
		[(ListWindowController *)[self dataSource] startEditAtColumn: column row: row];
	}

//	if (insertNewline) {
//		/*  Insert empty event and continue  */
//		if (row > numRows - 1)
//			row = numRows - 1;
//		[[self dataSource] startEditAtRow: row insertMode: YES];
//	} else {
//		if (row > numRows - 2)
//			row = numRows - 2;
//		[self selectRow: row byExtendingSelection: NO];
//		[self editColumn: column row: row withEvent: nil select: YES];
//	}
	return YES;
}

/*  Keyboard navigation during _not_ editing.
 *  Command+Return: insert a new event after the current event and start editing.
 *  Command+Enter: start editing at the current cell.
 *  Delete, Backspace: delete selected events.
*/
- (void)keyDown:(NSEvent *)theEvent
{
	int row;
	BOOL insertFlag;
	unichar charCode = [[theEvent charactersIgnoringModifiers] characterAtIndex: 0];
	int modifierFlags = [theEvent modifierFlags];
	if ((modifierFlags & NSCommandKeyMask) != 0 && (charCode == NSCarriageReturnCharacter || charCode == NSEnterCharacter)) {
		/*  Enter edit mode  */
		if ([self numberOfSelectedRows] == 1) {
			int32_t position;
			row = (int)[self selectedRow];
			if (charCode == NSCarriageReturnCharacter) {
				insertFlag = YES;
				if (row < [self numberOfRows] - 1)
					row++;
			} else {
				insertFlag = NO;
			}
			position = [(ListWindowController *)[self dataSource] eventPositionForTableRow: row];
			[(ListWindowController *)[self dataSource] startEditAtColumn: -1 creatingEventWithTick: kMDNegativeTick atPosition: position + 1];
			return;
		}
		NSBeep();
	} else if (charCode == NSBackspaceCharacter || charCode == NSDeleteCharacter) {
		if ([self numberOfSelectedRows] > 0)
			[(ListWindowController *)[self dataSource] deleteSelectedEvents: self];
		else NSBeep();
	} else [super keyDown:theEvent];
}

/*  Implement context menu  */
- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
	NSPoint pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
	int row = (int)[self rowAtPoint: pt];
	int column = (int)[self columnAtPoint: pt];
	NSRect cellFrame = [self frameOfCellAtColumn: column row: row];
	if (cellFrame.size.height > 0 && cellFrame.size.width > 0) {
		return [[[[self tableColumns] objectAtIndex: column] dataCell] menuForEvent: theEvent inRect: cellFrame ofView: self];
	} else return nil;
/*
	if (column == 1 && row >= 0 && row < [self numberOfRows] - 1 && [self selectedRow] == row)
		return [self menu];
	else return nil; */
}

- (void)setUnderlineRow:(int)row
{
	if (row == underlineRow)
		return;
	if (underlineRow >= 0)
		[self setNeedsDisplayInRect:[self rectOfRow:underlineRow]];
	underlineRow = row;
	if (underlineRow >= 0)
		[self setNeedsDisplayInRect:[self rectOfRow:underlineRow]];		
}

- (void)drawRow:(NSInteger)row clipRect:(NSRect)clipRect
{
    [super drawRow:row clipRect:clipRect];
    if (underlineRow == row) {
        float y;
        NSRect rowRect;
        rowRect = [self rectOfRow:underlineRow];
        y = rowRect.origin.y + rowRect.size.height - 2;
        [[NSColor grayColor] set];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(rowRect.origin.x + 1, y) toPoint:NSMakePoint(rowRect.origin.x + rowRect.size.width - 1, y)];
    }
}

/*
- (void)drawRect: (NSRect)aRect
{
	NSRect rowRect;
	[super drawRect:aRect];
	if (underlineRow >= 0) {
		float y;
		rowRect = [self rectOfRow:underlineRow];
        y = rowRect.origin.y + 10;
		[NSBezierPath strokeLineFromPoint:NSMakePoint(rowRect.origin.x + 1, y) toPoint:NSMakePoint(rowRect.origin.x + rowRect.size.width - 1, y)];
	}
}
*/

@end
