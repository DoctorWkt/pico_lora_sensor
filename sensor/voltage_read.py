import machine
import utime
from machine import Pin, ADC

# Read and print the ADC0 value
#
# $Revision: 1.5 $

sensor0 = ADC(Pin(26, Pin.IN))
sensor2 = ADC(Pin(28, Pin.IN))
smps= Pin(23, Pin.OUT)

def read_voltage():
    # Set the SMPS pin high to reduce ADC noise
    smps.value(1)
    
    # We read and average 100 ADC0 results,
    # using the ADC2 value to reduce the offset from zero
    voltlist= []
    for i in range (0, 100):
        # voltage= sensor0.read_u16()
        voltage= sensor0.read_u16() - sensor2.read_u16()
        # print(str(sensor0.read_u16()) + " minus " + str(sensor2.read_u16()))
        voltlist.append(voltage)
        
    # Set the SMPS pin low to reduce power consumption
    smps.value(0)
        
    avgvolt= sum(voltlist) / 100
    return(avgvolt)


while True:
    # Get a voltage reading and print it
    value= read_voltage()
    print(value)
    utime.sleep(0.25)
