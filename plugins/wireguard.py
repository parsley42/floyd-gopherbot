#!/usr/bin/python3
import ipaddress
import sys
import os
import subprocess
import urllib.request

from welld_devops import AccessVerifier
from gopherbot_v2 import Robot

bot = Robot()

WG_CONF = '/etc/wireguard/wg0.conf'
username = os.getenv("GOPHER_USER")

# Sensitive data is only available from a hidden command - mainly the PSK
is_hidden_command = os.getenv("GOPHER_HIDDEN_COMMAND")

# Command Line Arguments

executable = sys.argv.pop(0)
command = sys.argv.pop(0)

# needed for real robot
if command == "configure":
    exit(0)

def read_state():
    state = bot.CheckoutDatum("wg", True)
    if not state.exists:
        state.datum = {
            "Latest_IP": "",
            "Users": {}
        }
    return state

def read_wg_preamble():
    # read wg0.txt and store robot's private key
    preamble = ''
    with subprocess.Popen(['sudo', 'head', '-n', '6', WG_CONF], stdout=subprocess.PIPE) as p:
        preamble = p.stdout.read().decode()
        data = preamble.splitlines()
        base_IP = data[1].split(' ')[-1].strip()
        robot_port = data[3].split(' ')[-1].strip()

    return preamble, base_IP, robot_port

if command != "add-ip":
    preamble, base_IP, robot_port = read_wg_preamble()
    state = read_state()

def write_wg():
    global preamble
    formatted_entries = ""
    # iterate over the users in the state file and add entries to wg0.txt
    for user, devices in state.datum['Users'].items():
        for device, device_data in devices.items():
            formatted_entry = f"\n[Peer]\n" \
                          f"# {user} | {device}\n" \
                          f"PublicKey = {device_data['PublicKey']}\n" \
                          f"PreSharedKey = {device_data['PreSharedKey']}\n" \
                          f"AllowedIPs = {device_data['AllowedIPs']}"
            formatted_entries += "\n" + formatted_entry
    preamble += formatted_entries

    # output updated wg0.txt
    with subprocess.Popen(["sudo", "tee", WG_CONF], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL) as p:
        p.communicate(preamble.encode())
    if os.getenv("GOPHER_PROTOCOL") != "terminal":
        os.system("sudo systemctl reload wg-quick@wg0")

if command == "init":
    write_wg()
    exit(0)

def delete_user(username):
    # If the user exists in state.datum['Users'], remove it
    if username in state.datum['Users']:
        del state.datum['Users'][username]
        bot.UpdateDatum(state)
        write_wg()
        return True
    else:
        return False

def delete_device(device):
    if username in state.datum['Users'] and device in state.datum['Users'][username]:
        del state.datum['Users'][username][device]
        bot.UpdateDatum(state)
        write_wg()
        return True
    else:
        return False

def get_robot_IP():
    # retrieve robot IP
    url = 'https://cloudflare.com/cdn-cgi/trace'
    with urllib.request.urlopen(url) as response:
        data = response.read().decode('utf-8')
    # get only the ip line
    ip_line = [line for line in data.split('\n') if 'ip=' in line][0]
    robot_IP = ip_line.split('=')[-1]
    return robot_IP

def add_user_to_state(device, user_public):
    # Assigning IPs: if first entry, default to base_IP +1; else, increment latest IP by 1
    if state.datum["Latest_IP"] == "":
        base_interface = ipaddress.IPv4Interface(base_IP)
        base_network = base_interface.network.prefixlen
        user_IP = str(base_interface.ip + 1) + '/32'
        state.datum["Latest_IP"] = user_IP
    else:
        # Convert to IPv4Address for correct incrementing
        latest_interface = ipaddress.IPv4Interface(state.datum["Latest_IP"])
        latest_network = latest_interface.network.prefixlen
        user_IP = str(latest_interface.ip + 1) + '/32'
        state.datum["Latest_IP"] = user_IP

    # get robot port
    robot_IP = get_robot_IP()
    robot_IP = robot_IP + ":" + robot_port

    user_psk_str = subprocess.check_output(["wg", "genpsk"]).decode().strip()
    # new user to be added
    entry = {
        "PublicKey" : user_public,
        "PreSharedKey" : user_psk_str,
        "AllowedIPs" : user_IP,
    }

    # if user does not have a preexisting username, create one.
    # if so, add new device to the list of devices asssociated with the username
    if f"{username}" in state.datum["Users"]:
        if f"{device}" in state.datum["Users"][f"{username}"]:
            bot.CheckinDatum(state)
            bot.Say("Error: Device Already Added.")
            exit(0)
    else:
        state.datum["Users"][f"{username}"] = {}

    state.datum["Users"][f"{username}"][f"{device}"] = entry
    bot.UpdateDatum(state)
    write_wg()
    config = f"Robot_IP = {robot_IP} | USER_IP = {user_IP} | PSK = {user_psk_str}"

    return config

def get_user_device_config(device):
    # get user_IP
    if username in state.datum['Users'] and device in state.datum['Users'][username]:
        user_IP = state.datum['Users'][username][device]["AllowedIPs"]
        user_psk_str = state.datum['Users'][username][device]["PreSharedKey"]
    else:
        bot.Say(f"Error: User '{username}' or device '{device}' not found")
        exit(0)

    # get robot port
    robot_IP = get_robot_IP()
    robot_IP = robot_IP + ":" + robot_port

    config = f"Robot_IP = {robot_IP} | USER_IP = {user_IP} | PSK = {user_psk_str}"

    return config

if command == "admin-list-vpn-users":
    # dictionary of vpn devices grouped by user
    user_devices = {}
    for username, devices in state.datum['Users'].items():
        user_devices[username] = [device for device in devices.keys()]
    # list of strings containing user and devices
    user_list = []
    for username, devices in user_devices.items():
        devices_string = ', '.join(devices)
        user_list.append(f"{username}: {devices_string}")
    user_list_string = '\n'.join(user_list)

    if user_list_string:
        bot.Say(f"\n{user_list_string}")
    else:
        bot.Say("No Users Found.")
    exit(0)

if command == "admin-delete-vpn-user":
    username = sys.argv.pop(0).lower()
    if delete_user(username):
        bot.Say(f"User '{username}' deleted successfully.")
    else:
        bot.Say(f"User '{username}' not found.")
    exit(0)

if command == "add-device":
    if not is_hidden_command:
        bot.Say("Sorry, 'add-device' must be issued as a hidden command")
        exit(0)
    if not AccessVerifier.verify_allowed_access(bot, "dev VPC VPN configuration"):
        exit(0)    
    device = sys.argv.pop(0).lower()
    user_public = sys.argv.pop(0)
    config = add_user_to_state(device, user_public)
    bot.Say(f"VPN config data: {config}")
    exit(0)

if command == "list-vpn-devices":
    if username in state.datum['Users']:
        devices = state.datum['Users'][username]
        device_list = ', '.join(devices.keys())
        devices_message = f"Device(s) for user '{username}': {device_list}\n"
    else:
        devices_message = f"No devices found for user '{username}'\n"
    bot.Say(devices_message)
    exit(0)

if command == "delete-device":
    device = sys.argv.pop(0).lower()
    if delete_device(device):
        bot.Say(f"Device '{device}' deleted successfully.")
    else:
        bot.Say(f"Device '{device}' not found for user '{username}'.")
    exit(0)

if command == "get-vpn":
    if not is_hidden_command:
        bot.Say("Sorry, 'get-vpn' must be issued as a hidden command")
        exit(0)
    device = sys.argv.pop(0).lower()
    if username in state.datum['Users']:
        devices = state.datum['Users'][username]
        if device in devices:
            user_public = devices[device]["PublicKey"]
            config = get_user_device_config(device)
            bot.Say(f"VPN config data: {config}")
        else:
            bot.Say(f"Device '{device}' not found for user '{username}'")
    else:
        bot.Say(f"No devices found for user '{username}'")
    exit(0)

if command == "allow-ip":
    if is_hidden_command:
        bot.Say("Sorry, 'allow-ip' must be issued as a non-hidden command")
        exit(0)
    address = sys.argv.pop(0)
    try:
        addr = ipaddress.IPv4Network(address)
    except ValueError:
        bot.Say("Invalid/unparseable IP address")
        exit(0)
    if not addr.is_global:
        bot.Say("Address is not public/global")
        exit(0)

    # Get the iptables list and parse it into an array of source IP addresses
    iptables_list = subprocess.check_output(["sudo", "iptables", "-L", "ALLOW_VPN", "-n"]).decode()
    ip_list = [line.split()[3] for line in iptables_list.split('\n') if line.startswith('ACCEPT')]

    # Check if the address is already in the list
    if address in ip_list:
        bot.Say("IP already allowed")
    else:
        os.system(f"sudo iptables -A ALLOW_VPN -s {address} -j ACCEPT")
        bot.Say("IP address added")
    exit(0)

if command == "clear-vpn":
    # Remove all users from the state data
    state.datum['Users'] = {}
    state.datum["Latest_IP"] = ""
    bot.UpdateDatum(state)

    # Write the updated, empty state data to the WireGuard config
    write_wg()

    # Clear the ALLOW_VPN iptables chain
    os.system("sudo iptables -F ALLOW_VPN")

    bot.Say("Cleared all VPN users and devices, and emptied the ALLOW_VPN chain")
    exit(0)
