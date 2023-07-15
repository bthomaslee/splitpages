#! /bin/zsh

# This script will split indicated pages in half (i.e., divide a set of sets of double page-scan pages into a set of twice-as-long sets of single page-scan pages) and then re-insert those pages (now containing two pages for every one) into the the currently open pdf (overwriting it), if the user approves. If you're using Acrobat, the script will close and reopen the original pdf so that you can see the changes.
# Note that the dialog at the beginning requires you to enter page ranges in the form x-x, where "x" is a single, whole, real, indo-arabic number (i.e., you can't enter cpdf page range syntactical units such as "end" or "1-~1"). Separate ranges by a comma followed by a single space, if you want to enter multiple ranges. If a range is a single page, enter it as x-x. All page ranges must contain all/only pages that will be split. 

# Set up script.
integer_check(){
    # Note that this function analyzes any number with any decimals (even 1.00) as a non-integer.
    input=${1/#-}; if [[ $input =~ ^[0-9]+$ ]]; then output="y"; else output="n"; fi
}
generate_random_longnum(){
    zmodload zsh/datetime
    current_nano=$(strftime $epochtime[2])
    base_random=$(echo $((9 + current_nano % 99)))
    random_multiplier=$(echo $((9 + current_nano % 99)))
    random_longnum=$(($base_random*$random_multiplier+$current_nano*$current_nano))
}
create_partnerscript(){
    generate_random_longnum
    partnerscript="$cache_path/$random_longnum.sh"
    printf "#! /bin/zsh\n" > $partnerscript
    grant_permissions $partnerscript
}

create_cpdf_partnerscript(){
    create_partnerscript
    printf "cpdf" >> $partnerscript
}

grant_permissions(){
    chmod 755 $1
}
cache_path="/Users/$USER/.shell_tmp"
error_file="$cache_path/splitpages_errors.log"
if ! [[ -d "$cache_path" ]]; then mkdir -p "$cache_path"; fi
if ! [[ -z "$error_file" ]]; then touch "$error_file"; fi

# IFS
spaces=$(echo -en " ")
newlines=$(echo -en "\n\b")
IFS=$spaces

# Initiate script.
if [[ ${script_name:=null} = null ]]; then export script_name=$(basename $(ps -p $$ | awk '$1 != "PID" {print $(NF)}')); echo "\nInitiating $script_name."; fi

# Set initial variables.
os_is_macos="y"
get_active_pdf="n"
pdf_app="Adobe Acrobat.app"
icon_file="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarCustomizeIcon.icns"

if [[ $get_active_pdf = "y" ]]
    
    then

    # Confirm that there's an active pdf in Adobe Acrobat.
    original_pdf=$(osascript -e 'tell application "Adobe Acrobat" to set the output to the POSIX path of (get file alias of active doc)') &>/dev/null
    if [[ $original_pdf = "" ]]
        then 
        osascript -e 'display notification "❌ No active pdf in Adobe Acrobat. Unable to proceed." with title "Split PDF Pages"' &>/dev/null
        exit
    fi

    # Save the active pdf.
    open -a $pdf_app
    if [[ $pdf_app = "Adobe Acrobat.app" ]]; then cliclick kp:esc kd:cmd t:s ku:cmd; fi

    else

    # Confirm that the passed filepath points to an existing pdf.
    original_pdf="$1"
    cpdf -info $original_pdf &>/dev/null 2>$error_file
    if [[ $(grep "Failed to read PDF" $error_file | wc -l | bc ) -gt 0 ]]
        then
        if [[ "$os_is_macos" = "y" ]]
            then
            osascript -e 'display notification "❌ Unable to read pdf." with title "Split PDF Pages"' &>/dev/null
            exit
            else
            echo "❌ Unable to read pdf. Terminating shell script."
            exit
        fi
    fi

fi

# Get the filepath to the active pdf and lay groundwork for the script.
original_pdf_basename=$(basename $original_pdf)
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
backup_pdf="$cache_path/${original_pdf_basename%*.pdf}---$timestamp.pdf"
last_page=$(cpdf -pages $original_pdf) &>/dev/null

while true; do

    # Run initial dialogs; create arrays for the ranges with pages to split.
    display_alert1(){osascript -e 'display dialog "No page ranges entered." buttons ("Ok") default button 1 with icon POSIX file "'$icon_file'"' &>/dev/null}
    display_alert2(){osascript -e 'display dialog "Invalid page range value(s)." buttons ("Ok") default button 1 with icon POSIX file "'$icon_file'"' &>/dev/null}
    display_alert3(){osascript -e 'display dialog "Invalid separation of page ranges." buttons ("Ok") default button 1 with icon POSIX file "'$icon_file'"' &>/dev/null}
    page_ranges_input=$(osascript -e 'display dialog "Enter ranges of pages to split (e.g., 5-16, 27-34):" default answer "all" with icon POSIX file "'$icon_file'"')
    button_returned="$(printf "$page_ranges_input" | cut -d ":" -f2 | cut -d "," -f1 )"
    if [[ -z "$button_returned" ]]; then exit; fi
    text_returned="$(printf "$page_ranges_input" | cut -d ":" -f3 )"
    page_ranges_input="$text_returned"
    if [[ $page_ranges_input = "all" ]]; then page_ranges_input="1-$last_page"; fi
    if [[ $page_ranges_input = "" || $page_ranges_input = " " ]]; then display_alert1; exit; fi
    if [[ $page_ranges_input = "0" ]]; then display_alert1; exit; fi
    marginal_width_percent_dividend=$(osascript -e 'display dialog "Enter % of the page width to use as central margin:" default answer "20" with icon POSIX file "'$icon_file'"')
    button_returned="$(printf "$marginal_width_percent_dividend" | cut -d ":" -f2 | cut -d "," -f1 )"
    if [[ -z "$button_returned" ]]; then exit; fi
    text_returned="$(printf "$marginal_width_percent_dividend" | cut -d ":" -f3 )"
    marginal_width_percent_dividend="$text_returned"
    if [[ "$button_returned" = "Cancel" ]]; then exit; fi
    if [[ $marginal_width_percent_dividend = "" || $marginal_width_percent_dividend -eq 0 ]]; then osascript -e 'display dialog "Invalid percent value." buttons ("Ok") default button 1 with icon POSIX file "'$icon_file'"' &>/dev/null; exit; fi
    marginal_width_percent="$(echo "$marginal_width_percent_dividend/100" | bc -l)"
    set -A page_ranges_raw1 $(echo $page_ranges_input)
    page_ranges_raw2=()
    for page_range in $page_ranges_raw1; do page_ranges_raw2+="${page_range/,/ }"; done
    modrange_first_pages=(); modrange_last_pages=()
    num_page_ranges=$#page_ranges_raw2[@]; page_range_num=1
    until [[ $page_range_num -gt $num_page_ranges ]]; do
        modrange_first_pages+="${page_ranges_raw2[$page_range_num]%-*}"
        modrange_last_pages+="${page_ranges_raw2[$page_range_num]#*-}"
        let page_range_num++
    done

    # Confirm the validity of all values for page range(s) entered by user.
    ## Confirm that the user entered something (anything at all).
    if [[ $page_ranges_input = "" || $page_ranges_input = " " ]]; then display_alert1; exit; fi
    ## Confirm that, in the simple cases (single page-range input), simple input errors aren't present.
    if [[ $page_ranges_input = ? || $page_ranges_input = ?- || $page_ranges_input = ?\, || $page_ranges_input = ???\  || $page_ranges_input = ???\,? || $page_ranges_input = ??\,? || $page_ranges_input = ?\,? ]]; then display_alert2; exit; fi
    ## Confirm that the number of commas in the user input is one less than the number of page ranges entered.
    num_ranges=$(echo $page_ranges_input | grep -o \.-\. | wc -l | bc )
    num_commas=$(echo $page_ranges_input | grep -o \, | wc -l | bc )
    if ! [[ $num_commas -eq $(($num_ranges-1)) ]]; then display_alert3; exit; fi
    ## Confirm that the number of ranges followed by spaces is zero.
    num_ranges_followed_by_spaces=$(echo $page_ranges_input | grep -o \.-\.\  | wc -l | bc )
    if [[ $num_ranges_followed_by_spaces -gt 0 ]]
        then
        if [[ $num_ranges -eq 1 ]]; then osascript -e 'display dialog "Remove the space after the page range." buttons ("Ok") default button 1 with icon POSIX file "'$icon_file'"' &>/dev/null; exit; fi
        if [[ $num_ranges -gt 1 ]]; then display_alert3; exit; fi
    fi
    ## Confirm that all page range values are integers.
    for page_num in $modrange_first_pages; do
        integer_check "$page_num"
        if [[ $output = "n" ]]; then display_alert2; exit; fi
    done
    for page_num in $modrange_last_pages; do
        integer_check "$page_num"
        if [[ $output = "n" ]]; then display_alert2; exit; fi
    done
    ## Confirm that no value is zero.
    for page_num in $modrange_first_pages; do; if [[ $page_num -eq 0 ]]; then osascript -e 'display dialog "Page range values must be greater than 0." buttons ("Ok") default button 1 with icon POSIX file "'$icon_file'"' &>/dev/null; exit; fi; done
    for page_num in $modrange_last_pages; do; if [[ $page_num -eq 0 ]]; then osascript -e 'display dialog "Page range values must be greater than 0." buttons ("Ok") default button 1 with icon POSIX file "'$icon_file'"' &>/dev/null; exit; fi; done

    # Create new arrays for all page ranges; mark the ones with pages to split.
    range_first_page=1
    range_first_pages=(); range_last_pages=(); range_last_page=0; modrange_num=1; mod_codes=()
    update_ranges(){
        range_first_pages+="$range_first_page"
        range_last_pages+="$range_last_page"
        range_first_page=$(($range_last_page+1))
    }
    until [[ $range_first_page -gt $last_page || $loop_num -gt 6 ]]; do
        if [[ $modrange_first_pages[$modrange_num] -eq $range_first_page ]]
            then
            range_first_page="$modrange_first_pages[$modrange_num]"
            range_last_page="$modrange_last_pages[$modrange_num]"
            update_ranges
            mod_code+="y"
            let modrange_num++
            else
            if [[ $modrange_first_pages[$modrange_num] -eq 0 ]]
                then range_last_page=$last_page
                else range_last_page="$(($modrange_first_pages[$modrange_num]-1))"
            fi
            update_ranges
            mod_code+="n"
        fi
    done

    # Extract page ranges from original pdf; duplicate, crop, then interleave the marked ones; add all page range source pdfs to an array.
    source_pdfs=()
    remove_source_pdfs(){
        num_source_pdfs=$#source_pdfs[@]; source_pdf_num=1
        until [[ $source_pdf_num -gt $num_source_pdfs ]]; do
            rm $source_pdfs[$source_pdf_num]
            let source_pdf_num++
        done
    }
    cp "$original_pdf" "$backup_pdf"
    num_ranges=$#range_first_pages[@]; range_num=1; loop_num=1
    until [[ $range_num -gt $num_ranges || $loop_num -gt 3 ]]; do
        generate_random_longnum
        input_pdf=$original_pdf
        page_range="${range_first_pages[$range_num]}-${range_last_pages[$range_num]}"
        output_pdf="$cache_path/$random_longnum.pdf"
        cpdf $input_pdf $page_range -o $output_pdf &>/dev/null
        if [[ $mod_code[$range_num] = "y" ]]
            then
            generate_random_longnum
            input_pdf=$output_pdf
            odd_pdf="$cache_path/${random_longnum}-odd.pdf"
            cpdf $input_pdf -o $odd_pdf &>/dev/null
            even_pdf="$cache_path/${random_longnum}-even.pdf"
            cpdf $input_pdf -o $even_pdf &>/dev/null
            num_odd_pages=$(cpdf -pages $odd_pdf) &>/dev/null
            num_even_pages=$(cpdf -pages $even_pdf) &>/dev/null
            if ! [[ $num_odd_pages -eq $num_even_pages ]]
                then
                remove_source_pdfs
                exit
            fi
            num_pages=$(cpdf -pages $odd_pdf) &>/dev/null
            pi_all=$(cpdf -page-info $odd_pdf 1) &>/dev/null
            pi_1=${pi_all#*MediaBox: }
            pi_2=${pi_1%Cropbox:*}
            set -A media_box_coordinates $(echo $pi_2)
            width_px=$media_box_coordinates[3]
            height_px=$media_box_coordinates[4]
            half_width_px=$(($width_px/2))
            marginal_width_px=$(($width_px*$marginal_width_percent))
            modified_width_px=$(($half_width_px+$marginal_width_px))
            even_startx=$(($width_px-$modified_width_px))
            cpdf -cropbox "0 0 $modified_width_px $height_px" $odd_pdf -o $odd_pdf &>/dev/null
            cpdf -cropbox "$even_startx 0 $modified_width_px $height_px" $even_pdf -o $even_pdf &>/dev/null
            create_cpdf_partnerscript
            page_num=1
            until [[ $page_num -gt $num_pages ]]; do
                printf " $odd_pdf $page_num" >> $partnerscript
                printf " $even_pdf $page_num" >> $partnerscript
                let page_num++
            done
            printf " -o $output_pdf" >> $partnerscript
            printf " &>/dev/null" >> $partnerscript
            $partnerscript
            rm $partnerscript; rm $odd_pdf; rm $even_pdf
        fi
        source_pdfs+=$output_pdf
        let range_num++
        let loop_num++
    done

    # Combine the page range source pdfs; delete the source pdfs.
    modified_pdf="$cache_path/${original_pdf_basename}-$timestamp-splitpagespreview.pdf"
    cpdf $source_pdfs -o $modified_pdf &>/dev/null
    remove_source_pdfs

    # Ask if the generated pdf is as desired.
    if [[ $pdf_app = "Adobe Acrobat.app" ]]; then open -a $pdf_app; cliclick kp:esc kd:cmd t:w ku:cmd; open $modified_pdf; fi

    # Ask if the modified pdf is correct. 
    quality_code=$(osascript -e 'display dialog "Is this new pdf what you want?" buttons ("Yes", "No, Exit", "No, Start Over") default button 3 with icon POSIX file "'$icon_file'"' -e 'set output to button returned of the result')
    open -a $pdf_app
    cliclick kp:esc kd:cmd t:w ku:cmd
    if [[ $quality_code = "Yes" ]]
        then cp "$modified_pdf" "$original_pdf"; rm $modified_pdf; mv $backup_pdf "/Users/$USER/.Trash"
        else mv $modified_pdf "/Users/$USER/.Trash"; rm $backup_pdf
    fi
    open $original_pdf
    
    # Start over, if desired.
    if [[ "$quality_code" = "No, Start Over" ]]
        then continue
        else break
    fi

done