//
//  SaveErrorPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 2020/03/03.
//  Copyright 2020-2022 Toshi Nagata. All rights reserved.
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

#import "SaveErrorPanelController.h"
#import "NSWindowControllerAdditions.h"

@implementation SaveErrorPanelController

+ (BOOL)showSaveErrorPanelWithMessage:(NSString *)aMessage
{
    NSInteger res;
    id cont = [[SaveErrorPanelController alloc] initWithWindowNibName:@"SaveErrorPanel"];
	[[cont window] center];
    [cont setMessage:aMessage];
	res = [NSApp runModalForWindow:[cont window]];
	[[cont window] orderOut:nil];
    [cont release];
    return (res == 1);
}

- (void)windowDidLoad
{
    [errorMessage setFont:[NSFont userFixedPitchFontOfSize:10]];
}

- (void)setMessage:(NSString *)aMessage
{
    [errorMessage insertText:aMessage replacementRange:NSMakeRange(-1, 0)];
}

- (IBAction)cancelPressed:(id)sender
{
    [NSApp stopModalWithCode:0];
}

- (IBAction)saveAnywayPressed:(id)sender
{
    [NSApp stopModalWithCode:1];
}

@end
