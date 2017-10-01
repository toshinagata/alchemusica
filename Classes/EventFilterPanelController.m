//
//  EventFilterPanelController.m
//  Alchemusica
//
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

#import "EventFilterPanelController.h"
#import "MDObjects.h"

NSString *gModeKey = @"mode",
	*gChannelPressureKey = @"channelPressure",
	*gNoteKey = @"note",
	*gPitchBendKey = @"pitchBend",
	*gPolyPressureKey = @"polyPressure",
	*gProgramKey = @"program",
	*gSysexKey = @"sysex",
	*gCCMetaKey = @"ccMeta";

NSString *gCCMetaNameKey = @"name",
	*gCCMetaSelectedKey = @"selected",
	*gCCMetaNumberKey = @"number";

static short *sCCMetaToObjectIndex;
static short *sObjectIndexToCCMeta;

@implementation EventFilterPanelController

+ (id)nameForCCMetaNumber: (int)number
{
	MDEvent event;
	int kind, code;
	char buf[64];
	MDEventInit(&event);
	if (number >= 128) {
		code = number - 128;
		kind = MDEventSMFMetaNumberToEventKind(code);
		MDSetKind(&event, kind);
		MDSetCode(&event, code);
	} else {
		MDSetKind(&event, kMDEventControl);
		MDSetCode(&event, number);
	}
	MDEventToKindString(&event, buf, sizeof buf);
	return [NSString stringWithUTF8String: buf + 1];
}

- (id)init
{
	self = [super initWithWindowNibName: @"EventFilterPanel"];
	if (self == nil)
		return nil;
	if (sCCMetaToObjectIndex == NULL) {
		//  cc/meta number <-> object index conversion table
		int i, j;
		static const short wellKnowns[] = {
			0, /* Bank select MSB */
			1, /* Modulation */
			5, /* Portamento time */
			6, /* Data entry MSB */
			7, /* Volume */
			10, /* Pan */
			11, /* Expression */
			32, /* Bank select LSB */
			64, /* Hold */
			98, /* NRPN LSB */
			99, /* NRPN MSB */
			100, /* RPN LSB */
			101, /* RPN MSB */
			kMDMetaText + 128,
			kMDMetaMarker + 128,
			kMDMetaTempo + 128,
			kMDMetaTimeSignature + 128,
			kMDMetaKey + 128,
			-1 };
		sCCMetaToObjectIndex = (short *)malloc(sizeof(short) * 256);
		sObjectIndexToCCMeta = (short *)malloc(sizeof(short) * 256);
		for (i = 0; i < 256; i++)
			sObjectIndexToCCMeta[i] = sCCMetaToObjectIndex[i] = -1;
		for (i = 0; wellKnowns[i] >= 0; i++) {
			sObjectIndexToCCMeta[i] = wellKnowns[i];
			sCCMetaToObjectIndex[wellKnowns[i]] = i;
		}
		for (j = 0; j < 256; j++) {
			if (sCCMetaToObjectIndex[j] >= 0)
				continue;
			sObjectIndexToCCMeta[i] = j;
			sCCMetaToObjectIndex[j] = i;
			i++;
		}
	}
		
	return self;
}

- (void)ccMetaPopUpMenuSelected: (id)sender
{
	//  Set the text and cc/meta number for the selected row
	int idx = (int)[ccMetaTableView selectedRow];
	int tag = (int)[sender tag];
	id obj;
	if (idx < 0)
		return;
	obj = [[ccMetaFilters arrangedObjects] objectAtIndex: idx];
	[obj setValue: [NSNumber numberWithInt: tag] forKey: gCCMetaNumberKey];
	[obj setValue: [sender title] forKey: gCCMetaNameKey];
}

- (void)windowDidLoad
{
	NSMutableDictionary *dict;

	[super windowDidLoad];

	{
		//  Set up the popup menu
		NSMenu *menu, *submenu;
		menu = [[[NSMenu alloc] initWithTitle: @"Meta and CC"] autorelease];
		[menu addItemWithTitle: @"Control" action: nil keyEquivalent: @""];
		submenu = MDMenuWithControlNames(self, @selector(ccMetaPopUpMenuSelected:), 0);
		[[menu itemAtIndex: 0] setSubmenu: submenu];
		[menu addItemWithTitle: @"Meta" action: nil keyEquivalent: @""];
		submenu = MDMenuWithMetaNames(self, @selector(ccMetaPopUpMenuSelected:), 128);
		[[menu itemAtIndex: 1] setSubmenu: submenu];
		[ccMetaPopUp setMenu: menu];
	}

	dict = [NSMutableDictionary dictionary];
	[filters setContent: dict];
	[[filters content] setValue: [NSNumber numberWithInt: 0] forKey: gModeKey];
}

- (void)setMode: (int)mode
{
	[[filters content] setValue: [NSNumber numberWithInt: mode] forKey: gModeKey];
}

- (int)mode
{
	return [[[filters content] valueForKey: gModeKey] intValue];
}

- (void)select: (BOOL)flag forKey: (id)key
{
	[[filters content] setValue: [NSNumber numberWithBool: flag] forKey: key];
}

- (BOOL)isSelectedForKey: (id)key
{
	return [[[filters content] valueForKey: key] boolValue];
}

- (IBAction)okPressed:(id)sender
{
	[[NSApplication sharedApplication] endSheet: [self window] returnCode: 1];
}

- (id)ccMetaFilters
{
	return [ccMetaFilters arrangedObjects];
}

- (void)addNewCCMetaFilter: (int)number selected: (BOOL)selected
{
	[ccMetaFilters addObject:
		[NSMutableDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt: number], gCCMetaNumberKey,
			[NSNumber numberWithBool: selected], gCCMetaSelectedKey,
			[[self class] nameForCCMetaNumber: number], gCCMetaNameKey,
			nil]];
}

- (IBAction)cancelPressed:(id)sender
{
	[[NSApplication sharedApplication] endSheet: [self window] returnCode: 0];
}

- (IBAction)addNewCCMetaEntry: (id)sender
{
	[self addNewCCMetaFilter: 0 selected: YES];
}

@end
