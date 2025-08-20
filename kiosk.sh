#!/bin/bash
#: Title: kiosk.sh
#: Author: Neal T. Bailey <nealosis@gmail.com>
#: Created: 08/01/2025
#: Updated: 08/20/2025
#: Purpose: terminal client for the Kitchen-Kiosk Recipes API
#
#: Usage: Usage: ./kiosk.sh [-r <recipe_id>] [-s <search_term>] [-l <page_size>] [-c <category_id>] [-i] [-h] [-v]
#: Options:
#:  -r, --recipe <recipe_id>	 Print details of a specific recipe by ID
#:  -s, --search <search_term>	 Search for recipes by title
#:  -l, --limit  <page_size>	 Number of results
#:  -c, --category <category_id> Prints recipes by category
#:  -i, --ingredient 		     Searches for ingredients in a recipe
#:  -h, --help			         Display this help message
#:  -v, --version			     Display version information
#
# Examples: 
#:  ./kiosk.sh -r 123		    Print the full recipe with the ID of 123
#:  ./kiosk.sh -s chocolate -i	Search for recipes containing chocolate
#:  ./kiosk.sh -s pie -l 5	    Search for first 5 recipes with pie in the title
#:  ./kiosk.sh --category		Print all categories in the database
#
# Changes:
#   V0.1.0   - initial release
#   V0.1.1   - added ability to set number of results returned
#   V0.1.2   - added ability to search for recipes by category
#   V0.1.3   - added support for spaces in search terms
#   V0.1.4   - added support for searching by ingredient
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
optionusage="Usage: $0 [-r <recipe_id>] [-s <search_term>] [-l <page_size>] [-c <category_id>] [-i] [-h] [-v]\n\n Options:\n  -r, --recipe <recipe_id>\tPrint details of a specific recipe by ID\n  -s, --search <search_term>\tSearch for recipes by title\n  -l, --limit  <page_size>\tNumber of results\n  -c, --category <category_id>\tPrints recipes by category\n  -i, --ingredient \t\tSearches for ingredients in a recipe\n  -h, --help\t\t\tDisplay this help message\n  -v, --version\t\t\tDisplay version information"
optionexamples="Examples:\n  $0 -r 123\t\tPrint the full recipe with the ID of 123\n  $0 -s chocolate -i\tSearch for recipes containing chocolate\n  $0 -s pie -l 5\tSearch for first 5 recipes with pie in the title\n  $0 --category\t\tPrint all categories in the database\n"
date_of_creation="2025-08-20"
version=0.1.4
author="Neal Bailey"
copyright="Baileysoft Solutions"

#
# Program variables
#
recipeApi="http://baileyfs02.baileysoft.lan:8001/api"
pageSize=50
recipeId=""
recipeSearch=""
searchType="recipe"
categoryId=""

# Start Function Definitions

#@ DESCRIPTION: URL encodes a string
#@ PARAMS: $1 - the string to encode
#@ REMARKS: This function encodes special characters in the string to make it safe for use in URLs
#@ OUTPUT: Encoded string
function urlencode() {
    local LANG=C
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c"
        esac
    done
}

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

#@ DESCRIPTION: Prints all the categories in the database
#@ REMARKS: Uses the recipe API to fetch the categories
function printCategories {    
    catsJson=$(curl -s --location "$recipeApi/categories")
    echo
    echo "Recipe Categories:"
    echo "----------------------------------------"
    echo "$catsJson" | jq -r '.[] | "[\(.catId)]\t\(.category)"' | column -ts $'\t'
    echo
}

#@ DESCRIPTION: Prints the most recent recipes
#@ REMARKS: Uses the recipe API to fetch the 20 most recent recipes
function printMostRecentRecipes {
    searchJson=$(curl -s --location "$recipeApi/recipes?sortcolumn=date&pagenumber=1&sortorder=desc&pagesize=$pageSize")
    echo
    echo "Most Recent Recipes:"
    echo "----------------------------------------"
    echo "$searchJson" | jq -r '.[] | "[\(.recId)]\t[\(.primaryCategory.category)]\t\(.title)"' | column -ts $'\t'
    echo
}

#@ DESCRIPTION: Prints recipes by category
#@ REMARKS: Uses the recipe API to fetch recipes in the provided category
function printRecipesByCategory {
    searchJson=$(curl -s --location "$recipeApi/recipes?sortcolumn=title&pagenumber=1&sortorder=asc&pagesize=$pageSize&categoryid=$categoryId")
    categoryName=$(echo "$searchJson" | jq -r '.[0].primaryCategory.category')
    echo
    echo "Recipes in Category ID [$categoryId] '$categoryName':"
    echo "----------------------------------------"
    echo "$searchJson" | jq -r '.[] | "[\(.recId)]\t\(.title)"' | column -ts $'\t'
    echo
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
    echo
}

#@ DESCRIPTION: Searches for recipes database by title
#@ PARAMS: $1 - the search term
#@ REMARKS: Uses the recipe API to search for recipes that match the search term
#@ OUTPUT: Prints a list of matching recipes with their IDs and titles
function searchRecipes {
    encodedSearch=$(urlencode "$1")    
    searchJson=$(curl -s --location "$recipeApi/recipes?sortcolumn=title&pagenumber=1&searchstring=$encodedSearch&sortorder=asc&pagesize=$pageSize&searchType=$searchType")
    echo
    echo "Results - ${searchType}s containing '$1':"
    echo "----------------------------------------"
    echo "$searchJson" | jq -r '.[] | "[\(.recId)]\t[\(.primaryCategory.category)]\t\(.title)"' | column -ts $'\t'
    echo
}

# End Function Definitions

# Command line argument handling
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--category)
            if [[ -n $2 && $2 =~ ^[0-9]+$ ]]; then
                categoryId="$2"
                shift 2
            else
                categoryId="0"
                shift 1
            fi
            ;;
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
            # Ensure that the next argument is not an option
            shift
            if [[ $# -eq 0 || $1 == -* ]]; then
                echo "Usage: $0 -s <search_term>"
                exit 1
            fi
            # Allow spaces in the search term
            recipeSearch=""
            while [[ $# -gt 0 && $1 != -* ]]; do
                recipeSearch+="$1 "
                shift
            done
            recipeSearch="${recipeSearch%" "}"  # trim trailing space
            ;;
        -l|--limit)
            if [[ -n $2 ]]; then
                pageSize="$2"                
                shift 2
            else
                echo "Usage: $0 -l <page size>"
                exit 1
            fi
            ;;
        -i|--ingredient)
            searchType="ingredient"; shift 1 ;;
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

#
# End Pre-requisite sanity check
#

# User passed a recipe Id, so fetch the recipe details
if [[ -n $recipeId ]]; then
    printRecipe "$recipeId"
    exit 0
fi

# User passed a search term, so search for recipes that match the search term
if [[ -n $recipeSearch ]]; then
    searchRecipes "$recipeSearch"
    exit 0
fi

# User passed category argument but didn't pass a category ID, print all categories
if [[ -n $categoryId && $categoryId -eq 0 ]]; then    
    printCategories
    exit 0
fi

# User passed a category ID, print recipes in that category
if [[ -n $categoryId ]]; then    
    printRecipesByCategory
    exit 0
fi

# No arguments passed, so print the most recent recipes
printMostRecentRecipes

exit 0