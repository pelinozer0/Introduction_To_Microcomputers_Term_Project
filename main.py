import serial  
import time

# ANA SINIF VE PROTOKOLLER

class HomeAutomationSystemConnection:
    def __init__(self):
        self.comPort = "COM1"
        self.baudRate = 9600
        self.serial_connection = None

    def setComPort(self, port):
        self.comPort = port

    def setBaudRate(self, rate):
        self.baudRate = rate

    def open(self):
        try:
            self.serial_connection = serial.Serial(self.comPort, self.baudRate, timeout=1)
            print(f"[BAĞLANTI] {self.comPort} başarıyla açıldı.")
            return True
        except Exception as e:
            print(f"[HATA] Port açılamadı ({self.comPort}): {e}")
            return False

    def close(self):
        if self.serial_connection and self.serial_connection.is_open:
            self.serial_connection.close()
            print("[BAĞLANTI] Port kapatıldı.")

    def send_byte(self, byte_data):
        if self.serial_connection and self.serial_connection.is_open:
            try:
                self.serial_connection.write(bytes([byte_data]))
            except:
                print("[HATA] Veri gönderilemedi.")

    def receive_byte(self):
        if self.serial_connection and self.serial_connection.is_open:
            try:
                data = self.serial_connection.read(1)
                if data:
                    return int.from_bytes(data, byteorder='big')
            except:
                pass
        return 0

    def update(self):
        pass

class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    def __init__(self):
        super().__init__()
        self.desiredTemperature = 0.0
        self.ambientTemperature = 0.0
        self.fanSpeed = 0

    def setDesiredTemp(self, temp):
        try:
            temp = float(temp)
            temp_int = int(temp)
            temp_frac = int((temp - temp_int) * 10)
            
            if temp_int > 63: temp_int = 63
            if temp_frac > 9: temp_frac = 9

            cmd_int = 0xC0 | temp_int
            cmd_frac = 0x80 | temp_frac

            self.send_byte(cmd_int)
            time.sleep(0.05)
            self.send_byte(cmd_frac)
            
            self.desiredTemperature = temp
            return True
        except ValueError:
            print("[HATA] Geçersiz sıcaklık değeri!")
            return False

    def update(self):
        try:
            self.send_byte(0x04) # High
            amb_high = self.receive_byte()
            time.sleep(0.02)
            self.send_byte(0x03) # Low
            amb_low = self.receive_byte()
            self.ambientTemperature = float(f"{amb_high}.{amb_low}")

            self.send_byte(0x05)
            self.fanSpeed = self.receive_byte()
        except:
            pass

    def getAmbientTemp(self): return self.ambientTemperature
    def getFanSpeed(self): return self.fanSpeed
    def getDesiredTemp(self): return self.desiredTemperature

class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    def __init__(self):
        super().__init__()
        self.curtainStatus = 0.0
        self.outdoorTemperature = 0.0
        self.outdoorPressure = 0.0
        self.lightIntensity = 0.0

    def setCurtainStatus(self, status):
        try:
            status = float(status)
            if status < 0: status = 0
            if status > 100: status = 100
            
            status_int = int(status)
            status_frac = int((status - status_int) * 10)
            
            cmd_int = 0xC0 | status_int
            cmd_frac = 0x80 | status_frac
            
            self.send_byte(cmd_int)
            time.sleep(0.05)
            self.send_byte(cmd_frac)
            
            self.curtainStatus = status
            return True
        except ValueError:
            print("[HATA] Geçersiz perde değeri!")
            return False

    def update(self):
        try:
            self.send_byte(0x08)
            l_high = self.receive_byte()
            time.sleep(0.02)
            self.send_byte(0x07)
            l_low = self.receive_byte()
            self.lightIntensity = float(f"{l_high}.{l_low}")
            
        except:
            pass

    def getCurtainStatus(self): return self.curtainStatus
    def getLightIntensity(self): return self.lightIntensity
    def getOutdoorTemp(self): return self.outdoorTemperature
    def getOutdoorPress(self): return self.outdoorPressure



# MENÜ VE UYGULAMA (Application)

def clear_screen():
    print("\n" * 2) 

def air_conditioner_menu(ac_sys):
    while True:
        clear_screen()
        ac_sys.update()
        
        print(f"--- AIR CONDITIONER SYSTEM (Port: {ac_sys.comPort}) ---")
        print(f"Home Ambient Temperature: {ac_sys.getAmbientTemp()} C")
        print(f"Home Desired Temperature: {ac_sys.getDesiredTemp()} C")
        print(f"Fan Speed:                {ac_sys.getFanSpeed()} rps")
        print("------------------------------------------------")
        print("1. Enter the desired temperature")
        print("2. Return")
        
        choice = input("Seçiminiz: ")
        
        if choice == '1':
            val = input("Enter Desired Temp (Örn: 24.5): ")
            ac_sys.setDesiredTemp(val)
            print("Sıcaklık gönderildi!")
            time.sleep(1)
        elif choice == '2':
            break

def curtain_menu(curtain_sys):
    while True:
        clear_screen()
        curtain_sys.update()
        
        print(f"--- CURTAIN CONTROL SYSTEM (Port: {curtain_sys.comPort}) ---")
        print(f"Outdoor Temperature: {curtain_sys.getOutdoorTemp()} C")
        print(f"Outdoor Pressure:    {curtain_sys.getOutdoorPress()} hPa")
        print(f"Curtain Status:      %{curtain_sys.getCurtainStatus()}")
        print(f"Light Intensity:     {curtain_sys.getLightIntensity()} Lux")
        print("------------------------------------------------")
        print("1. Enter the desired curtain status")
        print("2. Return")
        
        choice = input("Seçiminiz: ")
        
        if choice == '1':
            val = input("Enter Desired Curtain % (0-100): ")
            curtain_sys.setCurtainStatus(val)
            print("Perde ayarı gönderildi!")
            time.sleep(1)
        elif choice == '2':
            break

def main():
   
    PORT_KLIMA = "COM18"  
    PORT_PERDE = "COM14"  
    
    # Nesneleri oluştur
    ac_system = AirConditionerSystemConnection()
    ac_system.setComPort(PORT_KLIMA)
    
    curtain_system = CurtainControlSystemConnection()
    curtain_system.setComPort(PORT_PERDE)
    
    ac_system.open()
    curtain_system.open()

    while True:
        clear_screen()
        print("==================================")
        print("      HOME AUTOMATION MENU        ")
        print("==================================")
        print("1. Air Conditioner")
        print("2. Curtain Control")
        print("3. Exit")
        
        choice = input("Seçiminiz (1-3): ")
        
        if choice == '1':
            air_conditioner_menu(ac_system)
        elif choice == '2':
            curtain_menu(curtain_system)
        elif choice == '3':
            print("Çıkış yapılıyor...")
            ac_system.close()
            curtain_system.close()
            break
        else:
            print("Geçersiz seçim!")
            time.sleep(1)

if __name__ == "__main__":
    main()