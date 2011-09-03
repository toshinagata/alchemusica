/*
 *  MDRubyCore.h
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 08/03/19.
 *  Copyright 2008-2011 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDRubyCore__
#define __MDRubyCore__

VALUE Ruby_GetInterruptFlag(void);
VALUE Ruby_SetInterruptFlag(VALUE val);
VALUE Ruby_ObjectAtIndex(VALUE ary, int idx);
VALUE Ruby_funcall2_protect(VALUE recv, ID mid, int argc, VALUE *argv, int *status);

char *Ruby_FileStringValuePtr(VALUE *valp);
#define FileStringValuePtr(val) Ruby_FileStringValuePtr(&val)
VALUE Ruby_NewFileStringValue(const char *fstr);
VALUE Ruby_ObjToStringObj(VALUE val);

#include <ruby.h>

#endif /* __MDRubyCore__ */
