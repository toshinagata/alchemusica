//
//  MDRubyDialog.h
//  Alchemusica
//
//  Created by Toshi Nagata on 08/04/13.
//  Copyright 2008-2011 __MyCompanyName__. All rights reserved.
//

#ifndef __MDRubyDialog__
#define __MDRubyDialog__

#import <Cocoa/Cocoa.h>

#include <ruby.h>
#include "MDHeaders.h"

@interface MDRubyDialogController : NSWindowController {
	VALUE dval;  /*  Ruby object representing this object  */
	NSMutableArray *ditems;  /*  Array of dialog items  */
}
- (void)dialogItemAction: (id)sender;
- (void)setRubyObject: (VALUE)val;
- (void)addDialogItem: (id)ditem;
- (id)dialogItemAtIndex: (int)index;
- (int)searchDialogItem: (id)ditem;
@end

//  MRDialog class
extern VALUE cMRDialog;

void MRDialogInitClass(void);

#endif /* __MDRubyDialog__ */

