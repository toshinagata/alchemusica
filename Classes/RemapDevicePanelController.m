//
//  RemapDevicePanelCotroller.m
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

- (void)updateComboBoxContent
{
    id cell;
    int i, j, n1, n2;
    id aname;
    NSArray *array = [myDocument getDestinationNames];
    NSTableColumn *tableColumn = [myTableView tableColumnWithIdentifier:@"new"];
    cell = [tableColumn dataCell];
    if (cell == nil || ![cell isKindOfClass:[NSComboBoxCell class]]) {
        cell = [[[NSComboBoxCell alloc] init] autorelease];
        [cell setEditable: YES];
        [cell setCompletes: YES];
        [tableColumn setDataCell:cell];
    }
	n1 = MDPlayerGetNumberOfDestinations();
    n2 = (int)[array count];
	for (i = 0; i < n2; i++) {
        aname = [array objectAtIndex:i];
        if (i > n1) {
            aname = [[[NSAttributedString alloc] initWithString:aname attributes:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      [NSColor redColor], NSForegroundColorAttributeName, nil]] autorelease];
        }
		[cell addItemWithObjectValue:aname];
    }
    n1 = (int)[currentValues count];
    for (i = 0; i < n1; i++) {
        aname = [currentValues objectAtIndex:i];
        if ([aname isKindOfClass:[NSAttributedString class]])
            aname = [aname string];
        for (j = 0; j < n2; j++) {
            id bname = [cell itemObjectValueAtIndex:j];
            NSString *cname;
            if ([bname isKindOfClass:[NSAttributedString class]])
                cname = [bname string];
            else cname = bname;
            if ([aname isEqualToString:cname]) {
                [currentValues replaceObjectAtIndex:i withObject:bname];
                break;
            }
        }
    }
}

- (void)windowDidLoad
{
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
		for (j = (int)[initialValues count] - 1; j >= 0; j--) {
			if ([name isEqualToString: [initialValues objectAtIndex: j]])
				break;
		}
		if (j == -1) {
			/* Not found: register this */
			[initialValues addObject: name];
			j = (int)[initialValues count] - 1;
		}
		[deviceNumbers addObject: [NSNumber numberWithInt: j]];
    }
	currentValues = [[NSMutableArray allocWithZone: [self zone]] initWithArray: initialValues];
	
    [self updateComboBoxContent];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    //	NSLog(@"SheetDidEnd invoked with return code %d", returnCode);
    [[self window] close];
    if (stopModalFlag)
        [[NSApplication sharedApplication] stopModalWithCode: returnCode];
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
            id str = [currentValues objectAtIndex: j];
            if ([str isKindOfClass:[NSAttributedString class]])
                str = [str string];
        //    int32_t deviceNumber = MDPlayerGetDestinationNumberFromName([str cString]);
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

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [initialValues count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
row:(NSInteger)rowIndex
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
row:(NSInteger)rowIndex
{
	if ([@"new" isEqualToString: [aTableColumn identifier]]) {
        NSComboBoxCell *cell = [aTableColumn dataCell];
        int i, n = (int)[cell numberOfItems];
        if ([anObject isKindOfClass:[NSAttributedString class]])
            anObject = [anObject string];
        for (i = 0; i < n; i++) {
            id obj = [cell itemObjectValueAtIndex:i];
            NSString *sobj;
            if ([obj isKindOfClass:[NSAttributedString class]])
                sobj = [obj string];
            else sobj = obj;
            if ([sobj isEqualToString:anObject]) {
                anObject = obj;
                break;
            }
        }
        if (i >= n) {
            //  No match: we need to add a new item
            anObject = [[[NSAttributedString alloc] initWithString:anObject attributes:
                        [NSDictionary dictionaryWithObjectsAndKeys:
                         [NSColor redColor], NSForegroundColorAttributeName, nil]] autorelease];
            [cell addItemWithObjectValue:anObject];
        }
		if (rowIndex >= 0 && rowIndex < [currentValues count])
			[currentValues replaceObjectAtIndex: rowIndex withObject: anObject];
	}
}

@end
