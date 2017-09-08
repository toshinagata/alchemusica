//
//  AboutWindowController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 11/09/02.
//  Copyright 2011-2016 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "AboutWindowController.h"
#import "NSWindowControllerAdditions.h"
#import "MyAppController.h"

@implementation AboutWindowController

static id sSharedAboutWindowController;

+ (id)sharedAboutWindowController
{
	if (sSharedAboutWindowController == nil) {
		sSharedAboutWindowController = [[AboutWindowController alloc] initWithWindowNibName:@"AboutPanel"];
	}
	return sSharedAboutWindowController;
}

+ (void)showSplashWindow
{
	id cont = [AboutWindowController sharedAboutWindowController];
	[[cont window] center];
	[[cont viewWithTag:1000] setHidden:YES]; /* ok button */
	[[cont window] makeKeyAndOrderFront:nil];
}

+ (void)hideSplashWindow
{
	id cont = [AboutWindowController sharedAboutWindowController];
	[[cont window] orderOut:nil];
}

+ (void)showModalAboutWindow
{
	id cont = [AboutWindowController sharedAboutWindowController];
	[[cont window] center];
	[[cont viewWithTag:1001] setStringValue:@""];
	[[cont viewWithTag:1000] setHidden:NO];
	[NSApp runModalForWindow:[cont window]];
	[[cont window] orderOut:nil];
}

+ (void)setMessage:(NSString *)message
{
	id cont = [AboutWindowController sharedAboutWindowController];
	if ([[cont window] isVisible]) {
		if (message == nil)
			message = @"";
		[[cont viewWithTag:1001] setStringValue:message];
		[[[cont window] contentView] displayIfNeeded];
	}
}

- (void)windowDidLoad
{
	NSString *str1, *str2, *str3, *str4;
	int revision;
	
	[super windowDidLoad];
	
	//  Read version and last build info
	[(MyAppController *)[NSApp delegate] getVersion:&str1 copyright:&str2 lastBuild:&str3 revision:&revision];
	str4 = [versionText stringValue];
	str4 = [NSString stringWithFormat:str4, str1];
	[versionText setStringValue:str4];
	str4 = [myCopyrightText stringValue];
	str4 = [NSString stringWithFormat:str4, str2];
	[myCopyrightText setStringValue:str4];
	str4 = [lastBuildText stringValue];
	str4 = [NSString stringWithFormat:str4, str3];
	[lastBuildText setStringValue:str4];
	str4 = [revisionText stringValue];
	str4 = [NSString stringWithFormat:str4, revision];
	[revisionText setStringValue:str4];
	[(MyAppController *)[NSApp delegate] getRubyVersion:&str1 copyright:&str2];
	str3 = [rubyCopyrightText stringValue];
	str3 = [NSString stringWithFormat:str3, str1, str2];
	[rubyCopyrightText setStringValue:str3];
	
}

- (IBAction)okPressed:(id)sender
{
	[NSApp stopModal];
}

- (BOOL)windowShouldClose:(NSWindow *)sender
{
    [NSApp stopModal];
    return YES;
}

@end
