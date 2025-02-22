require "json"
require "date"
require "time"
require "tzinfo"

TIMEZONE = TZInfo::Timezone.get("America/Chicago")

def shift_by_employees(shift_data)
  format_time(shift_data).group_by { |shift| shift["EmployeeID"] }
end

def format_time(shift_data)
  shift_data.each do |shift|
    shift["StartTime"] = Time.parse(shift["StartTime"]).localtime(TIMEZONE)
    shift["EndTime"] = Time.parse(shift["EndTime"]).localtime(TIMEZONE)
  end
end

def shifts_overlap?(current_shift, next_shift)
  next_shift &&
    current_shift["EndTime"] > next_shift["StartTime"]
end

def duration(shift)
  (shift["EndTime"] - shift["StartTime"]) / 3600
end

def sunday(time)
  date = time.to_date
  date.prev_day(date.wday).to_s
end

def split_shift_duration(shift)
  sunday_start_shift = sunday(shift["StartTime"])
  sunday_end_shift = sunday(shift["EndTime"])
  {
    sunday_start_shift => (Time.parse(sunday_end_shift) - shift["StartTime"]) / 3600,
    sunday_end_shift => (shift["EndTime"] - Time.parse(sunday_end_shift)) / 3600
  }
end

def extract_overtime(duration)
  {
    regular_hours: [duration.to_f, 40].min.to_f.round(2),
    overtime_hours: [duration.to_f - 40, 0].max.to_f.round(2)
  }
end

def employee_summary_by_week(employee_id, shifts)
  summary_by_week = {}

  sorted_shifts = shifts.sort_by { |shift| shift["StartTime"] }

  sorted_shifts.each_with_index do |current_shift, index|
    next_shift = sorted_shifts[index + 1]

    if shifts_overlap?(current_shift, next_shift)
      current_shift[:valid] = false
      sunday_for_current_shift = sunday(current_shift["StartTime"])
      summary_by_week[sunday_for_current_shift] ||= {}
      if summary_by_week[sunday_for_current_shift][:invalid_shifts]
        summary_by_week[sunday_for_current_shift][:invalid_shifts].push(current_shift["ShiftID"])
      else
        summary_by_week[sunday_for_current_shift][:invalid_shifts] = [current_shift["ShiftID"]]
      end

      next_shift[:valid] = false
      sunday_for_next_shift = sunday(next_shift["StartTime"])
      summary_by_week[sunday_for_next_shift] ||= {}
      if summary_by_week[sunday_for_next_shift][:invalid_shifts]
        summary_by_week[sunday_for_next_shift][:invalid_shifts].push(next_shift["ShiftID"])
      else
        summary_by_week[sunday_for_next_shift][:invalid_shifts] = [next_shift["ShiftID"]]
      end
    end

    next if current_shift[:valid] == false

    sunday_for_shift_start = sunday(current_shift["StartTime"])
    sunday_for_shift_end = sunday(current_shift["EndTime"])

    summary_by_week[sunday_for_shift_start] ||= {}
    summary_by_week[sunday_for_shift_end] ||= {}

    if sunday_for_shift_start == sunday_for_shift_end
      if summary_by_week[sunday_for_shift_start][:duration]
        summary_by_week[sunday_for_shift_start][:duration] += duration(current_shift)
      else
        summary_by_week[sunday_for_shift_start][:duration] = duration(current_shift)
      end
    else
      split_duration = split_shift_duration(current_shift)
      if summary_by_week[sunday_for_shift_start][:duration]
        summary_by_week[sunday_for_shift_start][:duration] += split_duration[sunday_for_shift_start]
      else
        summary_by_week[sunday_for_shift_start][:duration] = split_duration[sunday_for_shift_start]
      end

      if summary_by_week[sunday_for_shift_end][:duration]
        summary_by_week[sunday_for_shift_end][:duration] += split_duration[sunday_for_shift_end]
      else
        summary_by_week[sunday_for_shift_end][:duration] = split_duration[sunday_for_shift_end]
      end
    end
  end
  summary_by_week
end

def weekly_shift_by_employee(raw_data)
  shift_by_employees(raw_data).flat_map do |employee_id, shifts|
    employee_summary_by_week(employee_id, shifts).map do |start_of_week, summary|
      hours = extract_overtime(summary[:duration])
      {
        EmployeeID: employee_id,
        StartOfWeek: start_of_week,
        RegularHours: hours[:regular_hours],
        OvertimeHours: hours[:overtime_hours],
        InvalidShifts: summary[:invalid_shifts].to_a
      }
    end
  end
end

default_file_name = "dataset.json"
puts "Please enter the dataset file name: (#{default_file_name})"
file_name = gets.chomp
file_name = default_file_name if file_name.empty?
file = File.read(file_name)
data = JSON.parse(file)

result = weekly_shift_by_employee(data).sort_by { |data| data[:StartOfWeek] }
File.write("response.json", JSON.pretty_generate(result))
puts result.map(&:to_json)
