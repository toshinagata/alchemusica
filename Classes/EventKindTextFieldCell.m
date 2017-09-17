//
//  EventKindTextFieldCell.m
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

#import "EventKindTextFieldCell.h"
#include "MDHeaders.h"

@implementation EventKindTextFieldCell

- (void)setIsGeneric: (BOOL)flag
{
	isGeneric = flag;
}

- (BOOL)isGeneric
{
	return isGeneric;
}

- (NSMenu *)menu
{
	if (!isNibLoaded) {
		isNibLoaded = [NSBundle loadNibNamed: @"EventKindTextFieldCell" owner: self];
	}
	return [super menu];
}

- (NSMenu *)menuForEvent:(NSEvent *)anEvent inRect:(NSRect)cellFrame ofView:(NSView *)aView
{
	id controlView = [self controlView];
	id menu = [self menu];
	lastMenuPoint = [aView convertPoint: [anEvent locationInWindow] fromView: nil];
	if ([controlView isKindOfClass: [NSTableView class]]) {
		int row = [controlView rowAtPoint: lastMenuPoint];
	//	int column = [controlView columnAtPoint: lastMenuPoint];
		id delegate = [controlView delegate];
		if ([delegate respondsToSelector: @selector(willUseMenu:forEvent:inRow:)])
			menu = [delegate willUseMenu: menu forEvent: anEvent inRow: row];
		[controlView selectRowIndexes: [NSIndexSet indexSetWithIndex: row] byExtendingSelection: NO];
//		[controlView editColumn: column row: row withEvent: anEvent select: YES];
	}
	return [self menu];
}

- (IBAction)eventKindMenuSelected:(id)sender
{
	MDEvent event;
	int tag, len;
	unsigned char *ucp;
	char buf[64];

	MDEventInit(&event);
	tag = [sender tag];	
	if (tag < 1000) {
		switch (tag) {
			case 0: /* Note */
				MDSetKind(&event, kMDEventNote);
				MDSetCode(&event, 60);
				break;
			case 1: /* Control (non-specific) */
				MDSetKind(&event, kMDEventControl);
				break;
			case 2: /* Pitch bend */
				MDSetKind(&event, kMDEventPitchBend);
				break;
			case 3: /* Program change */
				MDSetKind(&event, kMDEventProgram);
				break;
			case 4: /* Channel pressure */
				MDSetKind(&event, kMDEventChanPres);
				break;
			case 5: /* Polyphonic key pressure */
				MDSetKind(&event, kMDEventKeyPres);
				MDSetCode(&event, 60);
				break;
			case 6: /* Meta event (non-specific) */
				MDSetKind(&event, kMDEventMetaText);
				MDSetCode(&event, kMDMetaText);
				break;
			case 7: /* System exclusive */
				MDSetKind(&event, kMDEventSysex);
				break;
			default:
				return;
		}
	} else if (tag >= 1000 && tag < 2000) {
		/*  Control events  */
		MDSetKind(&event, kMDEventControl);
		MDSetCode(&event, (tag - 1000) & 127);
	} else if (tag >= 2000 && tag < 3000) {
		/*  Meta events  */
		switch (tag) {
			case 2000: /* tempo */
				MDSetKind(&event, kMDEventTempo);
				MDSetTempo(&event, 120.0);
				break;
			case 2001: /* meter */
				MDSetKind(&event, kMDEventTimeSignature);
				ucp = MDGetMetaDataPtr(&event);
				ucp[0] = 4; ucp[1] = 2; ucp[2] = 24; ucp[3] = 8;
				break;
			case 2002: /* key */
				MDSetKind(&event, kMDEventKey);
				break;
			case 2003: /* smpte */
				MDSetKind(&event, kMDEventSMPTE);
				break;
			case 2004: /* port */
				MDSetKind(&event, kMDEventPortNumber);
				break;
            case 2005: /* text */
			case 2006: /* copyright */
			case 2007: /* sequence */
			case 2008: /* instrument */
			case 2009: /* lyric */
			case 2010: /* marker */
			case 2011: /* cue */
			case 2012: /* program */
			case 2013: /* device */
				MDSetKind(&event, kMDEventMetaText);
				MDSetCode(&event, tag - 2005 + kMDMetaText);
				break;
			default:
				return;
		}
	} else return;

	/*  Get the authentic string representation  */
	len = 0;
	if (isGeneric) {
		switch (MDGetKind(&event)) {
			case kMDEventNote: strcpy(buf, "Note"); len = strlen(buf); break;
			case kMDEventKeyPres: strcpy(buf, ">KeyPressure"); len = strlen(buf); break;
		}
	}
	if (len == 0)
		len = MDEventToKindString(&event, buf, sizeof buf);
	if (len > 0) {
	#if 1
		id stringValue = [NSString stringWithUTF8String: buf];
		id controlView = [self controlView];
		if ([controlView isKindOfClass: [NSTableView class]]) {
			int column = [controlView columnAtPoint: lastMenuPoint];
			int row = [controlView rowAtPoint: lastMenuPoint];
			id myWindow = [controlView window];
			id fieldEditor;
			//  Start editing mode programatically, modify the text, and end editing mode.
			//  (This seems to be the most consistent way to modify a particular cell in
			//  the table view.)
			[controlView editColumn: column row: row withEvent: nil select: YES];
			fieldEditor = [myWindow fieldEditor: NO forObject: controlView];
			if (fieldEditor != nil) {
				//  shouldChangeTextInRange:replacementString: is absolutely necessary. If this
				//  call is omitted, then Cocoa binding of the table view does not work properly.
				[fieldEditor selectAll: nil];
				if ([fieldEditor shouldChangeTextInRange: [fieldEditor selectedRange] replacementString: stringValue]) {  //  Send notifications _before_ modification
					[fieldEditor setString: stringValue];    //  Change the value
					[fieldEditor didChangeText];             //  Send notifications _after_ modification
				}
				[myWindow makeFirstResponder: controlView];  //  End editing
			}
		}
	#else
		id stringValue = [NSString stringWithUTF8String: buf];
		id controlView = [self controlView];
		id dataSource;
		if ([controlView isKindOfClass: [NSTableView class]] && (dataSource = [controlView dataSource]) != nil) {
			int column = [controlView columnAtPoint: lastMenuPoint];
			int row = [controlView rowAtPoint: lastMenuPoint];
			id tableColumn = [[controlView tableColumns] objectAtIndex: column];
			[dataSource tableView: controlView setObjectValue: stringValue forTableColumn: tableColumn row: row];
		} else {
			[self setStringValue: stringValue];
			[NSApp sendAction: [self action] to: [self target] from: sender];
		}
	#endif
	}
}

@end
