//
//  ContextMenuTextFieldCell.h
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

#import <Cocoa/Cocoa.h>


@interface ContextMenuTextFieldCell : NSTextFieldCell {
	//  Implements a text field cell for which the content can be input via a context menu
	NSPoint lastMenuPoint;
    BOOL drawsUnderline;  //  Draw underline inside the cell
}
- (IBAction)contextMenuSelected:(id)sender;
- (void)setDrawsUnderline:(BOOL)underline;
- (BOOL)drawsUnderline;
@end

@interface NSObject(ContextMenuTextFieldCell)
- (id)willUseMenu:(id)menu ofCell:(ContextMenuTextFieldCell *)cell inRow:(int)row;
- (NSString *)stringValueForMenuItem:(id)item ofCell:(ContextMenuTextFieldCell *)cell inRow:(int)row;
@end
