//
//  RubyDialogController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 08/04/13.
//  Copyright 2008-2011 Toshi Nagata. All rights reserved.
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

#ifndef __RubyDialogController__
#define __RubyDialogController__

#import <Cocoa/Cocoa.h>

#include "ruby_dialog.h"

@interface RubyDialogController : NSWindowController {
	RubyValue dval;  /*  Ruby object representing this object  */
	NSMutableArray *ditems;  /*  Array of dialog items  */
@public
	NSTimer *myTimer;
	BOOL onKeyHandlerEnabled;
}
- (void)dialogItemAction: (id)sender;
- (void)setRubyObject: (RubyValue)val;
- (void)addDialogItem: (id)ditem;
- (id)dialogItemAtIndex: (int)index;
- (int)searchDialogItem: (id)ditem;
@end

#endif /* __MDRubyDialog__ */

