#!/bin/bash
#: Title: kiosk.sh
#: Author: Neal T. Bailey <nealosis@gmail.com>
#: Date: 08/01/2025
#: Updated: 07/15/2024
#: Purpose: Create a split VPN tunnel
#
#: Usage: ./kiosk.sh [-r <recipe_id>] [-s <search_term>] [-h] [-v]
#: Options:
#:  -r, --recipe <recipe_id>    Print details of a specific recipe by ID
#:  -s, --search <search_term>  Search for recipes by title
#:  -h, --help                  Display this help message
#:  -v, --version               Display version information
#
# Example: 
# ./kiosk.sh -r 123		        # Print details of recipe with ID 123
# ./kiosk.sh -s 'chocolate'     # Search for recipes with chocolate in the title
#
# Changes:
# V1.0   - initial release
#
# ----------------------------------------------------------------------
# GNU General Public License
# ----------------------------------------------------------------------
# Copyright (C) 2010-2018 Neal T. Bailey
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
#
# ----------------------------------------------------------------------

# Metadata
scriptname=${0##*/}
description="Kiosk Kiosk Recipes Client"
optionusage="Usage: $0 [-r <recipe_id>] [-s <search_term>] [-h] [-v]\n\n Options:\n  -r, --recipe <recipe_id>\tPrint details of a specific recipe by ID\n  -s, --search <search_term>\tSearch for recipes by title\n  -h, --help\t\t\tDisplay this help message\n  -v, --version\t\t\tDisplay version information"
optionexamples="Examples:\n  $0 -r 123\t\tPrint details of recipe with ID 123\n  $0 -s 'chocolate'\tSearch for recipes containing chocolate\n"
date_of_creation="2025-08-01"
version=1.0.0
author="Neal Bailey"
copyright="Baileysoft Solutions"

#
# Program variables
#
recipeApi="http://baileyfs02.baileysoft.lan:8001/api"
recipeId=""
recipeSearch=""

# Start Function Definitions

#@ DESCRIPTION: Prints usage information
function usage {
    printf "%s - %s\n" "$scriptname" "$description"
    printf "%s\n $optionusage"
    printf "%s\n\n $optionexamples"
}

#@ DESCRIPTION: Print version information
function version {
    printf "%s: %s\n" "$scriptname" "$description"
    printf "Release Date: %s\n" "$date_of_creation"
    printf "Version: %s\n" "$version"
    printf "Copyright: %s, %s\n" "$author" "$copyright"
}

#@ DESCRIPTION: Prints the most recent recipes
#@ REMARKS: Uses the recipe API to fetch the 20 most recent recipes
function printMostRecentRecipes {
    searchJson=$(curl -s --location "$recipeApi/recipes?sortcolumn=date&pagenumber=1&sortorder=desc&pagesize=20")
    echo "Most Recent Recipes:"
    echo "----------------------------------------"
    echo "$searchJson" | jq -r '.[] | "[\(.recId)]\t\(.title)"' | column -ts $'\t'
}

#@ DESCRIPTION: Prints the details of a specific recipe
#@ PARAMS: $1 - the Recipe ID
#@ REMARKS: Uses the recipe API to fetch details of a specific recipe by ID
#@ OUTPUT: Prints the recipe title, description, ingredients, and instructions
function printRecipe {
    echo 
    recipeJson=$(curl --location -s "$recipeApi/recipe/$1?expand=true")
    echo $recipeJson | jq -r '.title'
    echo "----------------------------------------"
    echo 
    echo $recipeJson | jq -r '.description'
    echo
    echo Ingredients:
    echo $recipeJson | jq -r '.ingredients[] | "  \(.ingredient)"'
    echo   
    echo Instructions:
    echo 
    echo $recipeJson | jq -r '.instructions' | sed 's/<br \/>/\n/g'
}

#@ DESCRIPTION: Searches for recipes database by title
#@ PARAMS: $1 - the search term
#@ REMARKS: Uses the recipe API to search for recipes that match the search term
#@ OUTPUT: Prints a list of matching recipes with their IDs and titles
function searchRecipes {
    searchJson=$(curl -s --location "$recipeApi/recipes?sortcolumn=title&pagenumber=1&searchstring=$1&sortorder=asc&pagesize=50")
    echo "$searchJson" | jq -r '.[] | "[\(.recId)]\t\(.title)"' | column -ts $'\t'
}

# End Function Definitions

# Command line argument handling
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--recipe)
            if [[ -n $2 && $2 =~ ^[0-9]+$ ]]; then
                recipeId="$2"                
                shift 2
            else
                echo "Usage: $0 -r <recipe_id>"
                exit 1
            fi
            ;;
        -s|--search)
            if [[ -n $2 ]]; then
                recipeSearch="$2"                
                shift 2
            else
                echo "Usage: $0 -s <search_term>"
                exit 1
            fi
            ;;
        -h|--help)
            usage; exit 0 ;;
        -v|--version)
            version; exit 0 ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

#
# Pre-requisite sanity check. These segments ensure nothing unexpected will prevent
# the process from completing at runtime due to unknown or invalid machine configuration. 
#

# Verify that jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to use this script."
    exit 1
fi

# Verify that curl is installed
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install curl to use this script."
    exit 1
fi

# Verify that the recipe API is reachable
if ! curl -s --head --request GET "$recipeApi/recipes" | grep "200 OK" > /dev/null; then
    echo "Error: Unable to reach the recipe API at $recipeApi. Please check your network connection or the API URL."
    exit 1
fi  

# End Pre-requisite sanity check

# User passed a recipe Id, so print the recipe details
if [[ -n $recipeId ]]; then
    printRecipe "$recipeId"
    exit 0
fi

# User passed a search term, so search for recipes that match the search term
if [[ -n $recipeSearch ]]; then
    searchRecipes "$recipeSearch"
    exit 0
fi

# No arguments passed, so print the most recent recipes
printMostRecentRecipes

exit 0