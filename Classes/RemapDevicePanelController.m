//
//  RemapDevicePanelCotroller.m
//
//  Created by Toshi Nagata.
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

#import "RemapDevicePanelController.h"
#import "MyMIDISequence.h"
#import "MyDocument.h"
#import "MDHeaders.h"

@implementation RemapDevicePanelController

- (id)initWithDocument: (MyDocument *)document trackSelection: (NSArray *)trackSelection
{
    self = [super initWithWindowNibName:@"RemapDevicePanel"];
	myDocument = [document retain];
    myTrackSelection = [trackSelection retain];
    return self;
}

- (void)dealloc
{
	[deviceNumbers release];
	[initialValues release];
	[currentValues release];
    [myTrackSelection release];
    [myDocument release];
	[super dealloc];
}

- (void)windowDidLoad
{
	NSTableColumn *tableColumn;
    NSComboBoxCell *cell;
	int i, j, n;
    NSEnumerator *en;
    id obj;

    /*  Update the device information before starting the dialog  */
    MDPlayerReloadDeviceInformation();
    
    if (myTrackSelection == nil) {
        NSMutableArray *array = [[NSMutableArray allocWithZone: [self zone]] init];
        n = [[myDocument myMIDISequence] trackCount];
        for (i = 0; i < n; i++)
            [array addObject: [NSNumber numberWithInt: i]];
        myTrackSelection = array;
    }
    
	initialValues = [[NSMutableArray allocWithZone: [self zone]] init];
	deviceNumbers = [[NSMutableArray allocWithZone: [self zone]] init];
    en = [myTrackSelection objectEnumerator];
	while ((obj = [en nextObject]) != nil) {
		NSString *name;
        i = [obj intValue];
        name = [[myDocument myMIDISequence] deviceName: i];
		if (name == nil) {
			[deviceNumbers addObject: [NSNumber numberWithInt: -1]];
			continue;
		}
		for (j = [initialValues count] - 1; j >= 0; j--) {
			if ([name isEqualToString: [initialValues objectAtIndex: j]])
				break;
		}
		if (j == -1) {
			/* Not found: register this */
			[initialValues addObject: name];
			j = [initialValues count] - 1;
		}
		[deviceNumbers addObject: [NSNumber numberWithInt: j]];
    }
	currentValues = [[NSMutableArray allocWithZone: [self zone]] initWithArray: initialValues];
	
    tableColumn = [myTableView tableColumnWithIdentifier:@"new"];
    cell = [[NSComboBoxCell alloc] init];
    [cell setEditable: YES];
//    [cell setBordered: NO];
    [cell setCompletes: YES];

	n = MDPlayerGetNumberOfDestinations();
	for (i = 0; i < n; i++) {
		char name[64];
		MDPlayerGetDestinationName(i, name, sizeof name);
		[cell addItemWithObjectValue: [NSString localizedStringWithFormat: @"%s", name]];
    }

	[tableColumn setDataCell: cell];
	[cell release];
}

- (void)beginSheetForWindow: (NSWindow *)parentWindow invokeStopModalWhenDone: (BOOL)flag
{
	NSWindow *window = [self window];
	stopModalFlag = flag;
	[[NSApplication sharedApplication] beginSheet: window
		modalForWindow: parentWindow
		modalDelegate: self
		didEndSelector: @selector(sheetDidEnd:returnCode:contextInfo:)
		contextInfo: nil];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
//	NSLog(@"SheetDidEnd invoked with return code %d", returnCode);
	[[self window] close];
	if (stopModalFlag)
		[[NSApplication sharedApplication] stopModalWithCode: returnCode];
}

- (IBAction)changeAction:(id)sender
{
	int i, j;
    NSEnumerator *en;
    id obj;
    en = [myTrackSelection objectEnumerator];
    i = 0;
    while ((obj = [en nextObject]) != nil) {
		j = [[deviceNumbers objectAtIndex: i] intValue];
		if (j >= 0 && j < [currentValues count]) {
            NSString *str = [currentValues objectAtIndex: j];
        //    long deviceNumber = MDPlayerGetDestinationNumberFromName([str cString]);
		//	[myDocument changeDeviceNumber: deviceNumber forTrack: [obj intValue]];
            [myDocument changeDevice: str forTrack: [obj intValue]];
        }
        i++;
	}
	[[NSApplication sharedApplication] endSheet: [self window] returnCode: 1];
//	[self release];
}

- (IBAction)dontChangeAction:(id)sender
{
	[[NSApplication sharedApplication] endSheet: [self window] returnCode: 0];
//	[self release];
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [initialValues count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
row:(int)rowIndex
{
	id identifier = [aTableColumn identifier];
	if ([@"current" isEqualToString: identifier])
		return [initialValues objectAtIndex: rowIndex];
	else if ([@"new" isEqualToString: identifier])
		return [currentValues objectAtIndex: rowIndex];
	else return nil;
}

- (void)tableView:(NSTableView *)aTableView
setObjectValue:(id)anObject
forTableColumn:(NSTableColumn *)aTableColumn
row:(int)rowIndex
{
	if ([@"new" isEqualToString: [aTableColumn identifier]]) {
		if (rowIndex >= 0 && rowIndex < [currentValues count])
			[currentValues replaceObjectAtIndex: rowIndex withObject: anObject];
	}
}

@end
