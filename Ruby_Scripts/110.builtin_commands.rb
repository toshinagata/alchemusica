#    Copyright (c) 2010-2017 Toshi Nagata. All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

class Sequence

#  The commands in this file are hardcoded so that the names should not be modified

def change_control_number
  hash = Dialog.run("Change Control Number") {
	@bind_global_settings = "change_control_number_dialog"
    layout(1,
	  layout(2,
	    item(:text, :title=>"Old control number"),
	    item(:textfield, :width=>40, :range=>[0, 127], :tag=>"old"),
	    item(:text, :title=>"New control number"),
	    item(:textfield, :width=>40, :range=>[0, 127], :tag=>"new")),
	  item(:checkbox, :title=>"Change only editable tracks", :tag=>"editable_only"),
	  item(:checkbox, :title=>"Change only selected events", :tag=>"selection_only"))
  }
  if hash[:status] == 0
    p hash
	old = Integer(hash["old"])
	new = Integer(hash["new"])
	editable_only = (hash["editable_only"] != 0)
	selection_only = (hash["selection_only"] != 0)
	each_track { |tr|
	  next if editable_only && !tr.editable?
	  sel = (selection_only ? tr.selection : tr.all_events)
	  sel = sel.select { |pt| pt.kind == :control && pt.code == old }
	  sel.modify_code([new])  #  modify_code(new) offsets the control numbers, which is not what we want
	}
  end
end

def shift_selected_events
  hash = Dialog.run("Shift Selected Events") {
    @bind_global_settings = "shift_selected_events_dialog"
	layout(1,
	  item(:text, :title=>"Shift amount"),
	  layout(6,
	    item(:text, :title=>"bar"),
	    item(:textfield, :width=>50, :tag=>"bar"),
	    item(:text, :title=>"beat"),
	    item(:textfield, :width=>50, :tag=>"beat"),
	    item(:text, :title=>"tick"),
	    item(:textfield, :width=>50, :tag=>"tick")),
	  item(:checkbox, :title=>"Shift backward", :tag=>"backward"))
  }
  p hash
  if hash[:status] == 0
	bar = hash["bar"].to_f
	beat = hash["beat"].to_f
	tick = hash["tick"].to_f
	sign = (hash["backward"] == 0 ? 1 : -1)
	if (bar == 0 && beat == 0)
	  delta = sign * tick
	else
	  range = tick_for_selection(true)
	  return if range[0] < 0
	  origin = tick_to_measure(range[0])
	  delta = measure_to_tick(origin[0] + sign * bar, origin[1] + sign * beat, origin[2] + sign * tick) - range[0]
	end
	p self
	each_track { |tr|
	  puts tr
	  next if !tr.editable?
	  tr.selection.modify_tick(delta)
	  #  The following code does _not_ work:
	  #     tr.each_selected { |pt| pt.tick = pt.tick + delta }
	  #  This is because changing tick may change the event position, so that 'pt'
	  #  may not point the correct event
	}
  end
end

def scale_selected_time_dialog
  s_tick, e_tick = self.editing_range
  return [] if s_tick < 0
  duration = e_tick - s_tick
  s_str = tick_to_measure(s_tick).join(".")
  e_str = tick_to_measure(e_tick).join(".")
  new_e_tick = e_tick
  new_duration = duration
  seq = self
  hash = Dialog.run("Scale Selected Time") {
    @bind_global_settings = "scale_selected_time_dialog"
    str_to_tick = proc { |str|
		a = str.scan(/\d+/)
		while a.length < 3; a.unshift("1"); end
		seq.measure_to_tick(a[0].to_i, a[1].to_i, a[2].to_i)
	}
    layout(1,
	  layout(2,
	    item(:text, :title=>"Start:"),
	    item(:textfield, :width=>100, :tag=>"start", :value=>s_str,
			:action=>proc { |it|
				new_e_tick = s_tick + value("new_duration").to_i
				s_tick = str_to_tick.call(it[:value])
				if s_tick > e_tick
					s_tick = e_tick
					set_value("start", seq.tick_to_measure(s_tick).join("."))
				end
				duration = e_tick - s_tick
				set_value("duration", sprintf("%d", duration))
				new_duration = new_e_tick - s_tick
				set_value("new_duration", sprintf("%d", new_duration))
			}),
	    item(:text, :title=>"End:"),
	    item(:textfield, :width=>100, :tag=>"end", :value=>e_str,
			:action=>proc { |it|
				e_tick = str_to_tick.call(it[:value])
				if s_tick > e_tick
					e_tick = s_tick
					set_value("end", seq.tick_to_measure(e_tick).join("."))
				end
				e_tick = s_tick + 1 if s_tick >= e_tick
				duration = e_tick - s_tick
				set_value("duration", sprintf("%d", duration))
			}),
	    item(:text, :title=>"Duration:"),
	    item(:textfield, :width=>50, :tag=>"duration", :value=>sprintf("%d", duration),
			:action=>proc { |it|
				duration = it[:value].to_i
				if duration < 0
					duration = 0
					set_value("duration", "0")
				end
				e_tick = s_tick + duration
				set_value("end", seq.tick_to_measure(e_tick).join("."))
			})
		),
	  layout(2,
	    item(:radio, :title=>"Specify end tick", :tag=>"new_end_radio", :value=>1),
	    item(:textfield, :width=>100, :tag=>"new_end", :value=>e_str,
			:action=>proc { |it|
				val_tick = str_to_tick.call(it[:value])
				if val_tick != new_e_tick
					set_value("new_duration", sprintf("%d", val_tick - s_tick))
					set_value("new_duration_radio", 0)
					set_value("new_end_radio", 1)
					new_e_tick = val_tick
					new_duration = new_e_tick - s_tick
				end
			}),
	    item(:radio, :title=>"Specify duration", :tag=>"new_duration_radio"),
	    item(:textfield, :width=>50, :tag=>"new_duration", :value=>duration.to_s,
			:action=>proc { |it|
				d = Integer(it[:value])
				if d != new_duration
					val_str = seq.tick_to_measure(s_tick + d).join(".")
					set_value("new_end", val_str)
					set_value("new_duration_radio", 1)
					set_value("new_end_radio", 0)
					new_duration = d
					new_e_tick = s_tick + d
				end
			}),
	    item(:checkbox, :title=>"Insert TEMPO event to keep absolute timings", :tag=>"insert_tempo"),
	    -1)
	)
  }
  if hash[:status] == 0
	return [s_tick, e_tick, new_duration, hash["insert_tempo"]]
  else
	return []
  end
end

#
#  Not used at present
#
def edit_sysex_dialog(track_no, event_no)
  seq = self
  tracks = (0...seq.ntracks).map { |i| seq.track(i).name }
  sysexs = seq.track(track_no).eventset { |pt| pt.kind == :sysex }
  sysex_names = sysexs.map { |pt|
    "#{pt.position + 1} - #{seq.tick_to_measure(pt.tick).join(':')}"
  }
  sysex_idx = sysexs.find_index { |pt| pt.position == event_no } || -1
  if (sysex_idx >= 0)
    data = seq.track(track_no).event(event_no).data
	sysex_data = ""
	data.each_with_index { |d, i|
	  next if i == 0 || i == data.length - 1  #  Remove f0 and f7
	  sysex_data += sprintf("%02X", d) + (i % 8 == 0 ? "\n" : " ")
	}
	sysex_data.strip!
	sysex_desc = sysex_data.dup
  end
  def check_data(data, old_data, pos)
    data = data.upcase
	#  Find 'bad character'; if present, remove all bad charaters, and
	#  set the selection at the position of the first bad character.
	idx = (data =~ /[^ \n0-9A-F]/)
	if idx
	  data.gsub!(/[^ \n0-9A-F]/, "")
	  pos = idx
	end
	#  Insert blanks after every two characters of alphanumeric
	i = 0
	x = 0
	d = data.dup
	data.each_byte { |n|
	  if (n >= 48 && n < 58) || (n >= 65 && n < 71)
	    if i == 2
		  d[x, 0] = " "
		  if pos >= x
		    pos += 1
		  end
		  i = 0
		  x += 1
		end
		i += 1
	  else
	    i = 0
	  end
	  x += 1
	}
	return d, pos
  end
  def data_to_desc(data)
    return data
  end
  hash = Dialog.run("Edit Sysex: " + seq.name, "OK", "Cancel", :resizable=>true) {
    old_data = sysex_data
    layout(1,
	  layout(2,
	    item(:text, :title=>"Track"),
		item(:popup, :subitems=>tracks, :value=>track_no),
	    item(:text, :title=>"Sysex"),
		item(:popup, :subitems=>sysex_names, :value=>sysex_idx),
		:flex=>[0,0,1,1,0,0]),
	  layout(1,
	    layout(1, item(:text, :title=>"F0 ->")),
	    item(:textview, :value=>sysex_data, :width=>200, :height=>100, :flex=>[0,0,0,0,1,1],
	      :tag=>"sysex_data",
	      :action=>lambda { |it|
		    data = it[:value]
		    sel = it[:selected_range]
		    data2, pos = seq.check_data(data, old_data, sel[0])
		    it[:value] = data2
		    if pos
		  	it[:selected_range] = [pos, pos]
		    else
		      it[:selected_range] = sel
		    end
		    old_data = data2
		    desc = seq.data_to_desc(data2)
		    set_value("sysex_desc", desc)
	      }),
		  item(:text, :title=>"-> F7", :align=>:right), :padding=>0),
	  item(:line),
	  item(:textview, :value=>sysex_desc, :width=>200, :height=>80, :flex=>[0,1,0,0,1,0],
	    :tag=>"sysex_desc"),
	  :flex=>[0,0,0,0,1,1])
  }
end

register_menu("Shift Selected Events...", :shift_selected_events, 1)
register_menu("Change Control Number...", :change_control_number, 1)

end
