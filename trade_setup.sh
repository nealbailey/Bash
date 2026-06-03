#!/bin/bash

market_ticker=SPX
futures_ticker=ES
is_short_straddle=false
is_short_ironfly=false
is_short_condor=false
is_short_vertical_spread=false
is_long_futures=false

#
# Metadata
#
scriptname=${0##*/}
description="Defines various trade setups."
usage="$scriptname"
optionusage="-e:\t Define a new ES Futures Trade\n  -f:\t Define a new Short Iron Butterfly Trade\n  -c:\t Define a new Short Iron Condor Trade\n  -s:\t Define a new Short Straddle Trade\n  -v:\t Define a new Short Vertical Spread Trade\n  -h:\t Print help (this screen)\n  -a:\t Print version info\n"
optionexamples=" ./"$scriptname" -s \n\n" 
date_of_creation="2025-12-15"
version=0.10.0
author="Neal T. Bailey"
copyright="Baileysoft Solutions"

#@ DESCRIPTION: Prints usage information
function usage()   
{ 
  printf "%s - %s\n" "$scriptname" "$description"
  printf "Usage: %s\n" "$usage"
  printf "%s  $optionusage"
  printf "\nExamples: %s\n $optionexamples"
}

#@ DESCRIPTION: Print version information
function version() 
{                  
  printf "%s: %s\n" "$scriptname" "$description"
  printf "Release Date: %s\n" "$date_of_creation"
  printf "Version: %s\n" "$version"  
  #printf "by %s, %d\n" "$author"  "${date_of_creation%%-*}"
  printf "Copyright: %s, %s\n" "$author" "$copyright"
}

#@ DESCRIPTION: Prints the trade setup table
#@ PARAM $1: The straddle short strike
#@ PARAM $2: The premium collected on the put side
#@ PARAM $3: The premium collected on the call side
#@ PARAM $4: The number of contracts sold
#@ PARAM $5: The trade profit target (percent)
#@ USAGE: print_trade_setup_straddle 6060 13 6.50 6.00 .18
function print_trade_setup_straddle() 
{
    short_strike=$1
    short_premium_put=$2
    short_premium_call=$3
    number_of_contracts=$4
    profit_target=$5

    short_premium_total=`python3 -c "print(round($short_premium_call+$short_premium_put,2))"`

    echo "0-DTE $market_ticker SHORT STRADDLE SETUP"
    echo "----------------------------------"
    echo "TRADE GENERATION TIMESTAMP: " $(date +%Y-%m-%dT%H:%M:%S) 

    #short_premium_total_2=`python3 -c "print(round($short_premium_total*100, 2))"`
    short_premium_total_2=`python3 -c "print(round($short_premium_total*$number_of_contracts, 2)*100)"`
    breakeven_call=`python3 -c "print($short_strike+$short_premium_call)"`
    breakeven_put=`python3 -c "print($short_strike-$short_premium_put)"`
    breakeven_trade_call=`python3 -c "print($short_strike+$short_premium_total)"`
    breakeven_trade_put=`python3 -c "print($short_strike-$short_premium_total)"`
    short_stop_price=`python3 -c "print(round($short_premium_total-($short_premium_total*$profit_target), 2))"`
    profit_target_val=`python3 -c "print($short_premium_total*$profit_target)"`
    profit_target_val2=`python3 -c "print(round($profit_target_val*100, 2))"`
    profit_target_val3=`python3 -c "print(int($profit_target*100))"`

    max_profit_if_stopped=`python3 -c "print(round(($short_premium_total-$short_stop_price)*$number_of_contracts,2)*100)"`
    max_profit_both_stopped=`python3 -c "print(round((($short_stop_price*$number_of_contracts*2)-$short_stop_price*$number_of_contracts),2)*100)"`

    printf "SHORT STRIKE: %s\n" "$short_strike" 
    printf "LEG PREMIUM: PUT $%s | CALL $%s\n" "$short_premium_put" "$short_premium_call"
    printf "TOTAL PREMIUM: %s ($%s)\n" "$short_premium_total" "$short_premium_total_2"
    printf "TOTAL CONTRACTS: %s\n" "$number_of_contracts"
    printf "BREAK-EVEN CALL STRIKE: %s (MAX %s)\n" "$breakeven_call" "$breakeven_trade_call"
    printf "BREAK-EVEN PUT STRIKE: %s (MAX %s)\n" "$breakeven_put" "$breakeven_trade_put"
    printf "PROFIT TARGET: %s (%s%%)\n" "$profit_target" "$profit_target_val3"
    printf "STOP-LIMIT PRICE: %s %s\n" "$short_stop_price"
    printf "MAX PROFIT SINGLE STOP: $%s\n" "$max_profit_if_stopped"
    printf "MAX LOSS FULL STOP: -$%s\n" "$max_profit_both_stopped"
}

#@ DESCRIPTION: Prints the trade setup table
#@ PARAM $1: The straddle short strike
#@ PARAM $2: The premium collected on the put side
#@ PARAM $3: The premium paid on the put side
#@ PARAM $4: The premium collected on the call side
#@ PARAM $5: The premium paid on the call side
#@ PARAM $6: The number of contracts sold
#@ PARAM $7: The trade profit target (percent)
#@ USAGE: print_trade_setup_ironfly 6060 13 6.50 6.00 .18
function print_trade_setup_ironfly() 
{
    short_strike=$1    
    short_premium_put=$2
    long_premium_put=$3
    short_premium_call=$4
    long_premium_call=$5
    number_of_contracts=$6
    profit_target=$7
    
    short_premium_put=`python3 -c "print(round($short_premium_put-$long_premium_put,2))"`
    short_premium_call=`python3 -c "print(round($short_premium_call-$long_premium_call,2))"`
    short_premium_total=`python3 -c "print(round($short_premium_call+$short_premium_put,2))"`

    echo "0-DTE $market_ticker SHORT IRONFLY SETUP"
    echo "----------------------------------"
    echo "TRADE GENERATION TIMESTAMP: " $(date +%Y-%m-%dT%H:%M:%S) 

    short_premium_total_2=`python3 -c "print(round($short_premium_total*$number_of_contracts, 2)*100)"`
    breakeven_call=`python3 -c "print($short_strike+$short_premium_call)"`
    breakeven_put=`python3 -c "print($short_strike-$short_premium_put)"`
    breakeven_trade_call=`python3 -c "print($short_strike+$short_premium_total)"`
    breakeven_trade_put=`python3 -c "print($short_strike-$short_premium_total)"`
    short_stop_price=`python3 -c "print(round($short_premium_total-($short_premium_total*$profit_target), 2))"`
    profit_target_val=`python3 -c "print($short_premium_total*$profit_target)"`
    profit_target_val2=`python3 -c "print(round($profit_target_val*100, 2))"`
    profit_target_val3=`python3 -c "print(int($profit_target*100))"`

    max_profit_if_stopped=`python3 -c "print(round(($short_premium_total-$short_stop_price)*$number_of_contracts,2)*100)"`
    max_profit_both_stopped=`python3 -c "print(round((($short_stop_price*$number_of_contracts*2)-$short_stop_price*$number_of_contracts),2)*100)"`

    printf "SHORT STRIKE: %s\n" "$short_strike"
    printf "LEG PREMIUM: PUT $%s | CALL $%s\n" "$short_premium_put" "$short_premium_call"
    printf "TOTAL PREMIUM: %s ($%s)\n" "$short_premium_total" "$short_premium_total_2"
    printf "TOTAL CONTRACTS: %s\n" "$number_of_contracts"
    printf "BREAK-EVEN CALL STRIKE: %s (MAX %s)\n" "$breakeven_call" "$breakeven_trade_call"
    printf "BREAK-EVEN PUT STRIKE: %s (MAX %s)\n" "$breakeven_put" "$breakeven_trade_put"
    printf "PROFIT TARGET: %s (%s%%)\n" "$profit_target" "$profit_target_val3"
    printf "STOP-LIMIT PRICE: %s %s\n" "$short_stop_price"
    printf "MAX PROFIT SINGLE STOP: $%s\n" "$max_profit_if_stopped"
    printf "MAX LOSS FULL STOP: -$%s\n" "$max_profit_both_stopped"
}

#@ DESCRIPTION: Prints the trade setup table
#@ PARAM $1: The short put strike
#@ PARAM $2: The premium collected on the put side
#@ PARAM $3: The premium paid on the put side
#@ PARAM $4: The short call strike
#@ PARAM $5: The premium collected on the call side
#@ PARAM $6: The premium paid on the call side
#@ PARAM $7: The number of contracts sold
#@ PARAM $8: The risk to reward (1-9)
#@ USAGE: print_trade_setup_ironCondor 5800 1.55 0.25 5900 1.00 0.35 1 4
function print_trade_setup_ironCondor() 
{
    short_strike_put=$1    
    short_premium_put=$2
    long_premium_put=$3
    short_strike_call=$4
    short_premium_call=$5
    long_premium_call=$6
    number_of_contracts=$7    
    risk_ratio=$8
    
    short_premium_put=`python3 -c "print(round($short_premium_put-$long_premium_put,2))"`
    short_premium_call=`python3 -c "print(round($short_premium_call-$long_premium_call,2))"`
    short_premium_total=`python3 -c "print(round($short_premium_call+$short_premium_put,2))"`

    echo "0-DTE $market_ticker SHORT IRON CONDOR SETUP"
    echo "----------------------------------"
    echo "TRADE GENERATION TIMESTAMP: " $(date +%Y-%m-%dT%H:%M:%S) 

    short_premium_total_2=`python3 -c "print(round($short_premium_total*$number_of_contracts, 2)*100)"`
    short_premium_total_3=`python3 -c "print(int($short_premium_total_2))"`
    short_legs_width=`python3 -c "print($short_strike_call-$short_strike_put)"`
    short_stop_price_put=`python3 -c "print($short_premium_put*($risk_ratio))"`
    max_loss_short_put=`python3 -c "print(round($short_stop_price_put-$short_premium_put, 2)*$number_of_contracts)"`
    max_loss_short_put2=`python3 -c "print($max_loss_short_put*100)"`
    max_loss_short_put3=`python3 -c "print(round($short_stop_price_put-$short_premium_total, 2)*$number_of_contracts*100)"`

    short_stop_price_call=`python3 -c "print(round($short_premium_call*($risk_ratio), 2))"`
    max_loss_short_call=`python3 -c "print(round($short_stop_price_call-$short_premium_call, 2)*$number_of_contracts)"`
    max_loss_short_call2=`python3 -c "print($max_loss_short_call*100)"`
    max_loss_short_call3=`python3 -c "print(round($short_stop_price_call-$short_premium_total, 2)*$number_of_contracts*100)"`

    printf "SHORT PUT STRIKE: %s\n" "$short_strike_put"
    printf "SHORT CALL STRIKE: %s\n" "$short_strike_call"
    printf "SHORT LEGS WIDTH: %s points\n" "$short_legs_width"
    printf "LEG PREMIUM: PUT $%s | CALL $%s\n" "$short_premium_put" "$short_premium_call"
    printf "TOTAL CONTRACTS: %s\n" "$number_of_contracts"
    printf "TOTAL PREMIUM: %s ($%s)\n" "$short_premium_total" "$short_premium_total_3"    
    printf "RISK TO REWARD RATIO: %s:1\n" "$risk_ratio"
    printf "SHORT OPTION STOP LIMITS: PUT %s | CALL %s\n" "$short_stop_price_put" "$short_stop_price_call"
    printf "MAX LOSS ON STOPS: PUT -$%s | CALL -$%s\n" "$max_loss_short_put2" "$max_loss_short_call2"
    printf "MAX LOSS SINGLE STOP: PUT -$%s | CALL -$%s\n" "$max_loss_short_put3" "$max_loss_short_call3"
}

#@ DESCRIPTION: Prints the trade setup table
#@ PARAM $1: The current market price (at the time of entry)
#@ PARAM $2: The short strike
#@ PARAM $3: The short premium collected
#@ PARAM $4: The long (protective) strike
#@ PARAM $5: The long premium paid
#@ PARAM $6: The number of contracts sold
#@ PARAM $7: The risk to reward (1-9)
#@ USAGE: print_trade_setup_ironCondor 5800 1.55 0.25 5900 1.00 0.35 1 4
function print_trade_setup_verticalSpread() 
{
    market_price=$1    
    short_strike=$2
    short_premium=$3
    long_strike=$4
    long_premium_paid=$5
    number_of_contracts=$6    
    risk_ratio=$7

    short_premium_total=`python3 -c "print(round($short_premium-$long_premium_paid,2))"`

    echo "0-DTE $market_ticker SHORT VERTICAL SPREAD SETUP"
    echo "----------------------------------"
    echo "TRADE GENERATION TIMESTAMP: " $(date +%Y-%m-%dT%H:%M:%S) 

    short_premium_total_2=`python3 -c "print(round($short_premium_total*$number_of_contracts, 2)*100)"`
    short_premium_total_3=`python3 -c "print(int($short_premium_total_2))"`
    short_legs_width=`python3 -c "print(abs($market_price-$short_strike))"`
    short_stop_price=`python3 -c "print($short_premium_total*($risk_ratio))"`
    max_loss=`python3 -c "print(round($short_stop_price-$short_premium_total, 2)*$number_of_contracts)"`
    max_loss2=`python3 -c "print($max_loss*100)"`
    max_loss3=`python3 -c "print(round($short_stop_price-$short_premium_total, 2)*$number_of_contracts*100)"`
    
    printf "%s MID PRICE: %s\n" "$market_ticker" "$market_price"
    printf "SHORT STRIKE: %s\n" "$short_strike"
    printf "MARGIN OF SAFETY: %s points\n" "$short_legs_width"
    printf "LEG PREMIUM: $%s\n" "$short_premium"
    printf "TOTAL CONTRACTS: %s\n" "$number_of_contracts"
    printf "TOTAL PREMIUM: %s ($%s)\n" "$short_premium_total" "$short_premium_total_3"    
    printf "RISK TO REWARD RATIO: %s:1\n" "$risk_ratio"
    printf "SHORT OPTION STOP LIMIT: %s\n" "$short_stop_price"
    printf "MAX LOSS ON STOP LIMIT: -$%s\n" "$max_loss3" 
}

#@ DESCRIPTION: Prints the trade setup table
#@ PARAM $1: The current market price (at the time of entry)
#@ PARAM $2: The max loss allowable per contract
#@ PARAM $3: The risk to reward (1-9)
#@ PARAM $4: The number of futures contracts
#@ USAGE: print_trade_setup_long_futures 6800 800 3 1
function print_trade_setup_long_futures() 
{
    entry_price=$1    
    max_loss_per_contract=$2
    risk_ratio=$3
    number_of_contracts=$4
    point_value=50  # ES futures point value

    echo "0-DTE /$futures_ticker FUTURES TRADE SETUP"
    echo "----------------------------------"
    max_loss_points=`python3 -c "print($max_loss_per_contract/$point_value)"`
    stop_price=`python3 -c "print($entry_price - $max_loss_points)"`
    take_profits_points=`python3 -c "print($max_loss_points*$risk_ratio)"`
    take_profits_price=`python3 -c "print($entry_price + $take_profits_points)"`
    max_loss_at_stop=`python3 -c "print($max_loss_per_contract*$number_of_contracts)"`
    max_profits_at_stop=`python3 -c "print($take_profits_points*$point_value*$number_of_contracts)"`
    
    printf "%s ENTRY PRICE: %s\n" "$futures_ticker" "$entry_price"
    printf "TOTAL CONTRACTS: %s\n" "$number_of_contracts"
    printf "RISK TO REWARD RATIO: 1:%s\n\n" "$risk_ratio"

    echo "STOP LOSS:"
    printf "%s (%s points)\n" "$stop_price" "$max_loss_points"
    echo "Order Type: STOP MARKET"
    printf "MAX LOSS: ($%s) + slippage\n\n" "$max_loss_at_stop" 

    echo "TAKE PROFIT:"
    printf "%s (%s points)\n" "$take_profits_price" "$take_profits_points"
    echo "Order Type: LIMIT"
    printf "MAX PROFIT: $%s\n\n" "$max_profits_at_stop" 

    echo "TRADE GENERATION TIMESTAMP: " $(date +%Y-%m-%dT%H:%M:%S) 
}

# Command-line arguments processing
optstring=sfhvcea
while getopts $optstring opt
do
  case $opt in  
  s) is_short_straddle="true";;
  c) is_short_condor="true";;
  f) is_short_ironfly="true";;
  v) is_short_vertical_spread=true;;
  e) is_long_futures=true;;
  h) usage; exit ;;
  a) version; exit ;;
  *) usage; exit ;;
  esac
done
shift "$(( $OPTIND - 1 ))"

if [[ $is_short_straddle == "true" ]]; then
    read -p "Enter Short Strike: " short_strike
    read -p "Enter Put Premium Collected: " short_premium_put
    read -p "Enter Call Premium Collected: " short_premium_call
    read -p "Enter Number of Contracts: " number_of_contracts
    read -p "Enter Profit Target (0-100): " profit_target
    clear
    print_trade_setup_straddle $short_strike $short_premium_put $short_premium_call $number_of_contracts .$profit_target
fi

if [[ $is_short_ironfly == "true" ]]; then
    read -p "Enter Short Strike: " short_strike
    read -p "Enter Short Put Premium Collected: " short_premium_put
    read -p "Enter long Put Premium Paid: " long_premium_put
    read -p "Enter Short Call Premium Collected: " short_premium_call
    read -p "Enter Long Call Premium Paid: " long_premium_call
    read -p "Enter Number of Contracts: " number_of_contracts
    read -p "Enter Profit Target (0-100): " profit_target
    clear
    print_trade_setup_ironfly $short_strike $short_premium_put $long_premium_put $short_premium_call $long_premium_call $number_of_contracts .$profit_target
fi

if [[ $is_short_condor == "true" ]]; then
    read -p "Enter Short Put Strike: " short_strike_put
    read -p "Enter Short Put Premium Collected: " short_premium_put
    read -p "Enter long Put Premium Paid: " long_premium_put
    read -p "Enter short Call Strike: " short_strike_call
    read -p "Enter Short Call Premium Collected: " short_premium_call
    read -p "Enter Long Call Premium Paid: " long_premium_call
    read -p "Enter Number of Contracts: " number_of_contracts
    read -p "Enter the risk to reward (1-9): " risk_to_reward
    clear
    print_trade_setup_ironCondor $short_strike_put $short_premium_put $long_premium_put $short_strike_call $short_premium_call $long_premium_call $number_of_contracts $risk_to_reward
    #print_trade_setup_ironCondor 5815 1.82 0.32 5965 1.50 0.20 1 4
fi

if [[ $is_short_vertical_spread == "true" ]]; then
    read -p "Enter Current Share Price: " market_price
    read -p "Enter Short Strike: " short_strike
    read -p "Enter Short Premium Collected: " short_premium
    read -p "Enter Long Strike: " long_strike
    read -p "Enter long Premium Paid: " long_premium_paid
    read -p "Enter Number of Contracts: " number_of_contracts
    read -p "Enter the risk to reward (1-9): " risk_to_reward
    clear
    print_trade_setup_verticalSpread $market_price $short_strike $short_premium $long_strike $long_premium_paid $long_premium_call $number_of_contracts $risk_to_reward
    #print_trade_setup_verticalSpread 5982 6040 1.17 6080 0.12 1 4
fi

if [[ $is_long_futures == "true" ]]; then
    read -p "Enter Current Share Price: " market_price
    read -p "Enter Max Loss Allowed (per contract): " max_loss
    read -p "Enter the risk to reward (1-9): " risk_to_reward
    read -p "Enter Number of Contracts: " number_of_contracts
    
    clear
    print_trade_setup_long_futures $market_price $max_loss $risk_to_reward $number_of_contracts
    #print_trade_setup_long_futures 6800 800 3 1
fi

