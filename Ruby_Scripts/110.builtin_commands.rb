#    Copyright (c) 2010-2012 Toshi Nagata. All rights reserved.
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
	old = Integer(hash["old"])
	new = Integer(hash["new"])
	editable_only = hash["editable_only"]
	selection_only = hash["selection_only"]
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
	  sysex_data += sprintf("%02X", d) + (i % 8 == 7 ? "\n" : " ")
	}
	sysex_desc = sysex_data
  end
  hash = Dialog.run("Edit Sysex", "OK", "Cancel", :resizable=>true) {
    layout(1,
	  layout(2,
	    item(:text, :title=>"Track"),
		item(:popup, :subitems=>tracks, :value=>track_no),
	    item(:text, :title=>"Sysex"),
		item(:popup, :subitems=>sysex_names, :value=>sysex_idx)),
	  item(:textview, :value=>sysex_data, :width=>200, :height=>100),
	  item(:textview, :value=>sysex_desc, :width=>200, :height=>80))
  }
end

end
