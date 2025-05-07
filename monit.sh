#!/usr/bin/env bash

# ==============================================
# Системный и диагностический мониторинг
# Версия 1.0
# 
# Возможности:
# - Мониторинг процессора, памяти, дисков, сети
# - Работа с процессами (/proc и управление)
# - Сохранение отчетов в файл
# ==============================================

set -e

DEFAULT_OUTPUT="output.log"

check_dependencies() {
    local missing=()
    
    for cmd in mpstat iostat ifstat free lsblk w lscpu ip ps; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if ! dpkg -s sysstat &>/dev/null; then
        missing+=("sysstat (пакет)")
    fi

    if ! dpkg -s ifstat &>/dev/null; then
        missing+=("ifstat (пакет)")
    fi

    if [[ ${#missing[@]} -ne 0 ]]; then
        echo "Ошибка: Отсутствуют зависимости: ${missing[*]}" >&2
        echo "Установите их командой:" >&2
        echo "  sudo apt-get install sysstat ifstat" >&2
        exit 1
    fi
}

show_help() {
    cat <<EOF
Использование: $0 [опции]

Опции:
  -p,  --proc [arg]        Работа с /proc (cpuinfo, meminfo, uptime, version, all)
  -c,  --cpu               Информация о процессоре
  -tp, --topproc           Топ-5 процессов по загрузке процессора
  -m,  --memory            Информация о памяти
  -d,  --disks             Информация о дисках
  -n,  --network           Информация о сети
  -u,  --users             Информация о пользователях
  -la, --loadaverage       Средняя нагрузка на систему
  -k,  --kill <PID>        Завершить процесс
  -o,  --output <файл>     Сохранить вывод в файл (по умолчанию: $DEFAULT_OUTPUT)
  -h,  --help              Показать справку

Примеры:
  $0 -m -o /tmp/mem.log    # Вывод информации о пямяти сохраняется в файл /tmp/memory.log
  $0 --topproc             # Показать топ-5 процессов по загрузке CPU
  $0 --proc cpuinfo        # Показать информацию о CPU из /proc
  $0 --kill 2341           # Завершить процесс с PID 2341
  $0 -c -m -o sys_info.log # Сохранить информацию в файл
EOF
    exit 0
}

show_proc() {
    local arg="$1"

    if [[ -z "$arg" ]]; then
echo "=== /proc directory ==="
echo "  cpuinfo   → /proc/cpuinfo"
echo "  meminfo   → /proc/meminfo"
echo "  uptime    → /proc/uptime"
echo "  version   → /proc/version"
echo "  stat      → /proc/stat"
echo "  mounts    → /proc/mounts"
echo
echo "Доступные параметры для --proc:"
echo "  cpuinfo   - Информация о процессоре"
echo "  meminfo   - Информация о памяти"
echo "  uptime    - Время работы системы"
echo "  version   - Версия ядра Linux"
echo "  stat      - Статистика процессов"
echo "  mounts    - Информация о монтировании"
echo "  all       - Вывести всё вышеуказанное"
        return 0
    fi

    case "$arg" in
        cpuinfo)
            echo "=== CPU Info ==="
            awk -F ': ' '
                /vendor_id/ { print "CPU Vendor: " $2 }
                /model name/ { print "CPU Model: " $2 }
                /cpu MHz/ { print "CPU Frequency (MHz): " $2 }
            ' /proc/cpuinfo | head -3
            ;;
        meminfo)
            echo "=== Memory Info ==="
            awk -F ': *' '
                /MemTotal/ { printf "Total Memory: %s\n", $2 }
                /SwapTotal/ { printf "Swap Memory: %s\n", $2 }
            ' /proc/meminfo
            ;;
        uptime)
            echo "=== System Uptime ==="
            read up idle < /proc/uptime
            days=$((${up%.*}/86400))
            hours=$(((${up%.*}%86400)/3600))
            minutes=$(((${up%.*}%3600)/60))
            seconds=$((${up%.*}%60))
            echo "Uptime: $days days, $hours hours, $minutes minutes, $seconds seconds"
            echo "Idle time: $(awk "BEGIN {print $idle/86400}") days"
            ;;
        version)
            echo "=== Linux Version ==="
            cat /proc/version
            ;;
        stat)
            echo "=== Process statistics ==="
            cat /proc/stat | head -10
            ;;
        mounts)
            echo "=== Mounting Info ==="
            cat /proc/mounts | head -10
            ;;
        all) 
        echo "=== Full /proc Information ==="
            show_proc cpuinfo
            show_proc meminfo
            show_proc uptime
            show_proc version
            show_proc stat
            show_proc mounts
            ;;
        *) echo "Ошибка: Неверный аргумент '$arg' для --proc." >&2
           echo "Допустимые значения: cpuinfo, meminfo, uptime, version, stat, mounts, all" >&2
            return 1
            ;;
    esac
}

show_cpu() {
    echo "=== CPU Usage ==="
    mpstat
    echo "=== CPU Info ==="
    lscpu | awk -F ': ' '/Model name|CPU MHz|CPU\(s\)/ {print $1 ": " $2}'
}

show_topproc() {
    echo "=== Top 5 CPU Processes ==="

    if command -v ps &>/dev/null; then
        processes=($(ps -eo pid,%cpu,comm --sort=-%cpu | head -6 | tail -5))
        
        echo "PID      %CPU   COMMAND"
        for ((i=0; i<${#processes[@]}; i+=3)); do
            printf "%-8s %-6s %s\n" "${processes[i]}" "${processes[i+1]}" "${processes[i+2]}"
        done
    else
        echo "Ошибка: ps недоступна, используем /proc" >&2
        
        echo "PID      CPU?   COMMAND"
        pids=($(ls /proc | grep '^[0-9]\+$' | head -5))

        for pid in "${pids[@]}"; do
            if [[ -f "/proc/$pid/stat" ]]; then
                comm=$(cat /proc/$pid/comm 2>/dev/null)
                cpu_usage=$(awk '{print $14+$15}' "/proc/$pid/stat")
                printf "%-8s %-6s %s\n" "$pid" "$cpu_usage" "$comm"
            fi
        done
    fi
}

show_memory() { echo "=== Memory Usage ==="; free -h; }

show_disks() {
    echo "=== Disk Info ==="
    lsblk
    echo "=== Disk Usage ==="
    df -h
    if command -v iostat &>/dev/null; then
        echo "=== I/O Statistics ==="
        iostat -dx
    else
        echo "iostat не установлен, статистика I/O недоступна"
    fi
}

show_network() {
    echo "=== Network Interfaces ==="
    ip -br a
    echo "=== Network Traffic ==="
    if command -v ifstat &>/dev/null; then
        printf "\n"
        ifstat -S 1 1
        printf "\n"
    else
        echo "ifstat не установлен, статистика трафика недоступна"
    fi
}

show_users() { echo "=== Active Users ==="; w; }

show_load_average() { echo "=== Load Average ==="; uptime; }

kill_process() {
    [[ -z "$1" || ! -d "/proc/$1" ]] && { echo "Ошибка: Некорректный PID" >&2; exit 1; }
   
    kill "$1" && echo "Процесс $1 завершен" || { echo "Ошибка: Не удалось завершить процесс $1" >&2; exit 1; }
}

save_output() {
    local filename="${1:-$DEFAULT_OUTPUT}"
    shift
    local commands=("$@")
    
    [[ -z "$filename" ]] && {
        echo "Ошибка: Не указано имя файла" >&2
        return 1
    }
    
    if [[ ${#commands[@]} -eq 0 ]]; then
        echo "Ошибка: Не указаны команды для выполнения" >&2
        return 1
    fi
    
    if ! touch "$filename" 2>/dev/null; then
        echo "Ошибка: Невозможно создать файл '$filename'" >&2
        return 1
    fi
    
    if ! [ -w "$filename" ]; then
        echo "Ошибка: Нет прав на запись в файл '$filename'" >&2
        return 1
    fi
    
    if real_path=$(realpath "$filename" 2>/dev/null); then
        echo "Сохранение вывода в: $real_path"
    else
        echo "Ошибка: нет прав для записи в '$filename'" >&2
        return 1
    fi

    > "$filename"
    
    for cmd in "${commands[@]}"; do
        if ! declare -f "$cmd" >/dev/null; then
            echo "Предупреждение: Команда '$cmd' не найдена, пропускаем" >> "$filename"
            continue
        fi
        
        echo -e "\n=== Результат $cmd ===" >> "$filename"
        
        if ! $cmd >> "$filename" 2>&1; then
            echo " [Ошибка при выполнении $cmd]" >> "$filename"
        fi
        
        echo -e "\n----------------------------------------" >> "$filename"
    done
    
    if [[ ! -s "$filename" ]]; then
        echo "Предупреждение: Файл '$filename' пуст" >&2
        return 2
    fi
    
    return 0
}

trap 'echo "Прерывание..."; exit 1' SIGINT SIGTERM

check_dependencies

[[ $# -eq 0 ]] && show_help

commands_to_run=()
output_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--proc)
            if [[ -n "$2" && "$2" != -* ]]; then
                commands_to_run+=("show_proc" "$2")
                shift 2
            else
                commands_to_run+=("show_proc" "")
                shift
            fi
            ;;
        -c|--cpu)
            commands_to_run+=("show_cpu" "")
            shift
            ;;
        -tp|--topproc)
            commands_to_run+=("show_topproc" "")
            shift
            ;;
        -m|--memory)
            commands_to_run+=("show_memory" "")
            shift
            ;;
        -d|--disks)
            commands_to_run+=("show_disks" "")
            shift
            ;;
        -n|--network)
            commands_to_run+=("show_network" "")
            shift
            ;;
        -u|--users)
            commands_to_run+=("show_users" "")
            shift
            ;;
        -la|--loadaverage)
            commands_to_run+=("show_load_average" "")
            shift
            ;;
        -k|--kill)
            if [[ -n "$2" && "$2" != -* ]]; then      
                commands_to_run+=("kill_process" "$2")
                shift 2
            else
                echo "Ошибка: --kill требует PID" >&2
                exit 1
            fi
            ;;
         -o|--output)                                  
            if [[ -n "$2" && "$2" != -* ]]; then
                output_file="$2"
                shift 2
            else
                output_file="$DEFAULT_OUTPUT"
                shift
            fi
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Ошибка: Неизвестная команда '$1'" >&2
            show_help
            ;;
    esac
done

if [[ ${#commands_to_run[@]} -eq 0 ]]; then
    echo "Ошибка: Не указаны команды для выполнения" >&2
    exit 1
fi

if [[ -n "$output_file" ]]; then
    if real_path=$(realpath "$output_file" 2>/dev/null); then
        echo "Сохранение вывода в: $real_path"
    else
        echo "Ошибка: нет прав для записи в '$output_file'" >&2
        exit 1
    fi

    if ! touch "$output_file" 2>/dev/null || ! [ -w "$output_file" ]; then
        echo "Ошибка: не удается записать в '$output_file'" >&2
        exit 1
    fi   

    > "$output_file"

    for ((i=0; i<${#commands_to_run[@]}; i+=2)); do
        func="${commands_to_run[i]}"
        arg="${commands_to_run[i+1]}"
        
        echo -e "\n=== Результат $func $arg ===" >> "$output_file"

        if ! "$func" "$arg" >> "$output_file" 2>&1; then
            echo "[Ошибка при выполнении $func $arg]" >> "$output_file"
        fi

        echo -e "\n----------------------------------------" >> "$output_file"
    done
else
    for ((i=0; i<${#commands_to_run[@]}; i+=2)); do
        func="${commands_to_run[i]}"
        arg="${commands_to_run[i+1]}"
        "$func" "$arg"
    done
fi
