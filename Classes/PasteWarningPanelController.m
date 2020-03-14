//
//  PasteWarningPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 2020/03/14.
//  Copyright 2020 Toshi Nagata. All rights reserved.
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

#import "PasteWarningPanelController.h"
#import "NSWindowControllerAdditions.h"
#import "MyAppController.h"

@implementation PasteWarningPanelController

+ (id)createPasteWarningPanelControllerOfType:(int)aType
{
    PasteWarningPanelController *cont;
    NSString *nibName;
    switch (aType) {
        case kPasteWarningTypeTooFewTargets:
            nibName = @"PasteWarningTooFewTargets";
            break;
        case kPasteWarningTypeTooManyTargets:
            nibName = @"PasteWarningTooManyTargets";
            break;
        case kPasteWarningTypeConductorShouldBeEditable:
            nibName = @"PasteWarningConductorShouldBeEditable";
            break;
        case kPasteWarningTypeConductorShouldNotBeEditable:
            nibName = @"PasteWarningConductorShouldNotBeEditable";
            break;
        default:
            return nil;
    }
    cont = [[[PasteWarningPanelController alloc] initWithWindowNibName:nibName] autorelease];
    cont->type = aType;
    return cont;
}

- (void)windowDidLoad
{
    id obj;
    int n;
    returnCode = 1;
    switch (type) {
        case kPasteWarningTypeTooFewTargets:
            obj = MyAppCallback_getObjectGlobalSettings(@"paste.toofewtargets");
            n = (obj ? [obj intValue] : 1);
            if (n == 1) {
                [radio1 setState:NSOnState];
                [radio2 setState:NSOffState];
            } else {
                [radio1 setState:NSOffState];
                [radio2 setState:NSOnState];
            }
            break;
        case kPasteWarningTypeTooManyTargets:
            obj = MyAppCallback_getObjectGlobalSettings(@"paste.toomanytargets");
            n = (obj ? [obj intValue] : 1);
            if (n == 1) {
                [radio1 setState:NSOnState];
                [radio2 setState:NSOffState];
            } else {
                [radio1 setState:NSOffState];
                [radio2 setState:NSOnState];
            }
            break;
    }
}

- (void)setMainMessageWithInteger:(int)n1 and:(int)n2
{
    NSString *str;
    [[self window] center];  //  Dummy code for loading window
    if (mainMessage == nil)
        return;
    str = [mainMessage stringValue];
    str = [str stringByReplacingOccurrencesOfString:@"%1" withString:[NSString stringWithFormat:@"%d", n1]];
    str = [str stringByReplacingOccurrencesOfString:@"%2" withString:[NSString stringWithFormat:@"%d", n2]];
    [mainMessage setStringValue:str];
}

- (int)runSheetModalWithWindow:(NSWindow *)window
{
    NSModalSession session;
    NSInteger result;
    session = [NSApp beginModalSessionForWindow:window];
    [NSApp beginSheet:[self window] modalForWindow:window modalDelegate:self didEndSelector: @selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:nil];
    while ((result = [NSApp runModalSession:session]) == NSRunContinuesResponse)
        ;
    [NSApp endModalSession:session];
    [self close];
    switch (type) {
        case kPasteWarningTypeTooFewTargets:
            if (result == 1 || result == 2)
                MyAppCallback_setObjectGlobalSettings(@"paste.toofewtargets", [NSNumber numberWithInteger:result]);
            break;
        case kPasteWarningTypeTooManyTargets:
            if (result == 1 || result == 2)
               MyAppCallback_setObjectGlobalSettings(@"paste.toomanytargets", [NSNumber numberWithInteger:result]);
            break;
    }
    return (int)result;
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    [[self window] close];
    [NSApp stopModalWithCode:returnCode];
}

- (IBAction)radioSelected:(id)sender
{
    returnCode = (int)[sender tag];
    /*  On MacOS 10.8 and later, the radio group behavior is automatically implemented. However, on MacOS 10.6 and 10.7, we should handle it manually (because NSMatrix is made deprecated).  */
    if (sender == radio1)
        [radio2 setState:NSOffState];
    else if (sender == radio2)
        [radio1 setState:NSOffState];
}

- (IBAction)cancelPressed:(id)sender
{
    [NSApp endSheet:[self window] returnCode:0];
}

- (IBAction)pastePressed:(id)sender
{
    [NSApp endSheet:[self window] returnCode:returnCode];
}

@end
