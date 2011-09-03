//
//  LoadingPanelController.m
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

#import "LoadingPanelController.h"

@implementation LoadingPanelController

- (id)initWithTitle: (NSString *)title andCaption: (NSString *)caption
{
    self = [super initWithWindowNibName:@"LoadingPanel"];
	[[self window] setTitle: title];
	[textField setStringValue: caption];
	return self;
}

- (id)beginSession
{
	session = [[NSApplication sharedApplication] beginModalSessionForWindow: [self window]];
	return self;
}

- (BOOL)runSession
{
	return ([[NSApplication sharedApplication] runModalSession: session] == NSRunContinuesResponse);
}

- (id)endSession
{
	[[NSApplication sharedApplication] endModalSession: session];
	return self;
}

- (void)windowDidLoad
{
	canceled = NO;
	[indicator setDoubleValue: 0.0];
}

- (void)setProgressAmount: (double)amount
{
	if (amount >= 0.0 && amount <= 100.0) {
		[indicator setIndeterminate: NO];
		[indicator setDoubleValue: amount];
	} else {
		[indicator setIndeterminate: YES];
		[indicator startAnimation: self];
	}
}

- (void)setCaption: (NSString *)caption
{
	[textField setStringValue: caption];
}

- (BOOL)canceled
{
	return canceled;
}

- (IBAction)cancelAction:(id)sender
{
	canceled = YES;
}

@end
