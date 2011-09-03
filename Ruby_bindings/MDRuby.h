/*
 *  MDRuby.h
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

#ifndef __MDRuby__
#define __MDRuby__

#include "MDHeaders.h"

#include <ruby.h>

#ifndef RSTRING_PTR
#define RSTRING_PTR(_s) (RSTRING(_s)->ptr)
#endif
#ifndef RSTRING_LEN
#define RSTRING_LEN(_s) (RSTRING(_s)->len)
#endif

#ifndef RARRAY_PTR
#define RARRAY_PTR(_a) (RARRAY(_a)->ptr)
#endif
#ifndef RARRAY_LEN
#define RARRAY_LEN(_a) (RARRAY(_a)->len)
#endif

#include "MDRubyExtern.h"
#include "MDRubyEventSet.h"
#include "MDRubyCore.h"
#include "MDRubySequence.h"
#include "MDRubyTrack.h"
#include "MDRubyPointer.h"

#include "ruby_dialog.h"

#endif /* __MDRuby__ */
