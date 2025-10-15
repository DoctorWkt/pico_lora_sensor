# Code to read the voltage from a 12V battery
# and to send it as a UDP message to a server for logging.
#
# Note: we send the raw ADC value, not the actual voltage.
# The server will do the conversion.
#
# (c) 2025 Warren Toomey, GPL3, $Revision: 1.9 $

# import network
# import socket
import rp2
import machine
from machine import Pin, ADC
import time
import utime
from config_batt import *


# Blink the LED for 0.1 seconds
def blink_led():
    led.value(1)
    time.sleep(0.1)
    led.value(0)
    
# Sample ADC0 to get a raw "voltage" value
def read_voltage():
    # Set the SMPS pin high to reduce ADC noise
    smps.high()
    
    # We read and average 100 ADC0 results,
    # using the ADC2 value to reduce the offset from zero
    voltlist= []
    for i in range (0, 100):
        voltage= sensor0.read_u16() - sensor2.read_u16()
        voltlist.append(voltage)
        
    # Set the SMPS pin low to reduce power consumption
    smps.low()
        
    avgvolt= sum(voltlist) / 100
    return(avgvolt)

# Connect to the access point listed in
# the external config_batt.py file
def connect_to_AP(wlan):
    # Try to connect to the access point
    print("Connecting to", config['ssid'], '...')
    blink_led()
    wlan.connect(config['ssid'], config['password'])
    
    # Wait 30 seconds for a connection
    countdown=30
    while countdown > 0:
        if wlan.status() == 3:
            break
        print(' waiting for connection to', config['ssid'], "countdown", countdown)
        blink_led()
        time.sleep(1)
        countdown= countdown - 1
    
    # If we didn't get a connection, reset the board
    if wlan.status() != 3:
        print('Failed to connect to', config['ssid'], ', rebooting')
        time.sleep(1)
        machine.reset()
    
    # Otherwise we are connected
    status= wlan.ifconfig()
    print('Connected as IP', status[0])
    

# Initialise communications.
# Return the wlan, sock and address values
def init_wifi_comms():
    # Set the WiFi country to Australia
    # and enable WiFi
    rp2.country('AU')
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)

    # Connect to the wifi access point
    connect_to_AP(wlan)

    # Create a UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # Get the IP address for the server
    ai = socket.getaddrinfo(config['server'], config['serverport'])
    addr = ai[0][-1]
    print("Server is", addr)
    return wlan, sock, addr

# Send a LoRa command
def send_command(command):
    if isinstance(command, str):
        command = command.encode('ascii')
    uart.write(command + b"\r\n")
    utime.sleep(0.5)
    while uart.any():
        response = uart.read()
        if response:
            print("Response:", response.decode('utf-8', 'ignore'))

# Initialise LoRa communications.
def init_lora_comms():
    send_command("AT+ADDRESS=" + str(config['voltid']))
    send_command("AT+NETWORKID=5")
    send_command("AT+BAND=915000000")
    
# Send a reading to the server via LoRa
def send_lora_voltage(value):
    
    # Build the message
    mesg= "voltage:" + str(msgid) + ":" + str(config['voltid']) + ":" + str(value)
    loramesg= "AT+SEND=" + str(config['loraserver']) + "," + str(len(mesg)) + "," + mesg
    print(loramesg)
    
    # Send it three times to ensure that it gets through
    send_command(loramesg)
    blink_led()
    time.sleep(0.5)
    send_command(loramesg)
    blink_led()
    time.sleep(0.5)
    send_command(loramesg)
    blink_led()

# Send a reading to the server
def send_wifi_voltage(value, sock, addr):
    
    # Build the UDP message
    mesg= "voltage," + str(msgid) + "," + str(config['voltid']) + "," + str(value)
    print(mesg)
    
    # Send the data to the server three times to ensure the message gets through.
    sock.sendto(mesg, (addr))
    blink_led()
    time.sleep(0.5)
    sock.sendto(mesg, (addr))
    blink_led()
    time.sleep(0.5)
    sock.sendto(mesg, (addr))
    blink_led()

### MAIN PROGRAM ###
    
# Blink the LED to show that we have started
led = Pin('LED', Pin.OUT)
blink_led()
time.sleep(0.5)
blink_led()
time.sleep(0.5)
blink_led()

# Connect to the ADC0 sensor. We use the ADC2 sensor,
# wired to AGND, to reduce the offset
sensor0 = machine.ADC(0)
sensor2 = machine.ADC(2)

# By enabling the SMPS pin, we reduce the noise on
# the ADC samples, but it increases the power usage.
# So we turn it on, take samples, and turn it off again.
# smps= machine.Pin("WL_GPIO1")
smps= Pin(23, Pin.OUT)

# Connect to the LoRa transmitter
uart = machine.UART(0, baudrate=115200, tx=machine.Pin(0), rx=machine.Pin(1))

# Initialise the WiFi and get the server details
# wlan, sock, addr= init_comms()

# Initialise the LoRa module
init_lora_comms()


# Initialise the message-id to an arbitrary number
msgid= 0

# Loop getting sensor data
while True:
    
    # Reconnect to the Access Point
    # if we have lost our association
    # if not wlan.isconnected():
    #    connect_to_AP(wlan)
    #    status= wlan.ifconfig()
    #    print('Reconnected as IP', status[0])
        
    # Get a reading from the ADC
    value= read_voltage()

    # Send it to the server via WiFi
    # send_voltage(value, sock, addr)
    
    # Send it to the server via LoRa
    send_lora_voltage(value)
    
    # Bump the message-id for the future
    msgid= msgid + 1
    
    # Sleep for 1 minute before sending the next update
    time.sleep(60)
