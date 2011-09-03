//
//  EventKindTextFieldCell.h
//  Alchemusica
//
//  Created by Toshi Nagata on 08/03/01.
/*
    Copyright (c) 2008-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>


@interface EventKindTextFieldCell : NSTextFieldCell {
	//  Implements a text field cell that is specialized for editing the event kind
	BOOL isNibLoaded;
	BOOL isGeneric;    // YES if notes and poly-pressures are described as "Note" and ">KeyPressure" (without the note numbers) respectively.
	NSPoint lastMenuPoint;
}
- (void)setIsGeneric: (BOOL)flag;
- (BOOL)isGeneric;
- (IBAction)eventKindMenuSelected:(id)sender;

@end

@interface NSObject(EventKindTextFieldCell)
- (id)willUseMenu: (id)menu forEvent: (NSEvent *)anEvent inRow: (int)row;
@end
