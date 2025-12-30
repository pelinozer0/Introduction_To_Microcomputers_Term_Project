# Seri port iletişimi için gerekli kütüphaneler
import serial
import time


# Temel seri port bağlantı sınıfı
class HomeAutomationSystemConnection:
    def __init__(self):
        self.comPort = "COM1"  # Varsayılan port
        self.baudRate = 9600   # Standart baud hızı
        self.serial_connection = None

    def setComPort(self, port):
        self.comPort = port

    def setBaudRate(self, rate):
        self.baudRate = rate

    def open(self):
        """Seri portu aç ve buffer'ları temizle"""
        try:
            self.serial_connection = serial.Serial(self.comPort, self.baudRate, timeout=0.5)
            time.sleep(0.1)  # Port stabilizasyonu için bekle
            self.serial_connection.reset_input_buffer()  
            self.serial_connection.reset_output_buffer()
            print(f"[API] {self.comPort} baglantisi acildi.")
            return True
        except Exception as e:
            print(f"[API HATA] Port acilamadi ({self.comPort}): {e}")
            return False

    def close(self):
        if self.serial_connection and self.serial_connection.is_open:
            self.serial_connection.close()
            print("[API] Baglanti kapatildi.")

    def send_byte(self, byte_data):
        """Tek byte veri gönder"""
        if self.serial_connection and self.serial_connection.is_open:
            try:
                self.serial_connection.write(bytes([byte_data]))
                time.sleep(0.01)  # PIC'in işlemesi için zaman verilir.
            except Exception as e:
                print(f"[API] Send hatası: {e}")

    def receive_byte(self):
        """Tek byte veri oku"""
        if self.serial_connection and self.serial_connection.is_open:
            try:
                data = self.serial_connection.read(1)
                if data:
                    return int.from_bytes(data, byteorder='big')
            except Exception as e:
                print(f"[API] Receive hatası: {e}")
        return 0
    
    def update(self):
        pass


# Klima sistemi için özel sınıf
class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    def __init__(self):
        super().__init__()
        self.desiredTemperature = 25.0  # Hedef sıcaklık
        self.ambientTemperature = 0.0   # Ortam sıcaklığı
        self.fanSpeed = 0               # Fan hızı (RPS)

    def setDesiredTemp(self, temp):
        """Hedef sıcaklığı board'a gönder"""
        try:
            temp = float(temp)
            if temp < 10 or temp > 50:  # Geçerli aralık kontrolü
                return False
            
            # Tam ve ondalık kısımları ayır
            temp_int = int(temp)
            temp_frac = int((temp - temp_int) * 10)
            
            # 6-bit sınırı (protokol gereği)
            if temp_int > 63:
                temp_int = 63
            if temp_frac > 9:
                temp_frac = 9
            
            # UART protokolü: önce FRAC, sonra INT
            cmd_frac = 0x80 | temp_frac
            print(f"[SET] FRAC gönderiliyor: 0x{cmd_frac:02X} (temp_frac={temp_frac})")
            self.send_byte(cmd_frac)
            time.sleep(0.05)  
            
            cmd_int = 0xC0 | temp_int
            print(f"[SET] INT gönderiliyor: 0x{cmd_int:02X} (temp_int={temp_int})")
            self.send_byte(cmd_int)
            time.sleep(0.05)
            
            self.desiredTemperature = temp
            print(f"[SET] Hedef sıcaklık ayarlandı: {temp}°C")
            return True
        except Exception as e:
            print(f"[SET] Hata: {e}")
            return False

    def update(self):
        """Board'dan veri okuma (otonom mod için devre dışı)"""
        return


    def getAmbientTemp(self):
        return self.ambientTemperature
    
    def getFanSpeed(self):
        return self.fanSpeed
    
    def getDesiredTemp(self):
        return self.desiredTemperature


# Perde kontrol sistemi için özel sınıf
class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    def __init__(self):
        super().__init__()
        self.curtainStatus = 0.0          # Perde durumu (%)
        self.outdoorTemperature = 0.0     # Dış sıcaklık
        self.outdoorPressure = 0.0        # Dış basınç
        self.lightIntensity = 0.0         # Işık şiddeti (Lux)

    def setCurtainStatus(self, status):
        """Perde durumunu ayarla (0-100%)"""
        try:
            status = float(status)
            if status < 0:
                status = 0
            if status > 100:
                status = 100
            
            # Perde kontrol protokolü
            self.send_byte(0xB0)   
            time.sleep(0.05)       
            self.send_byte(int(status))
            
            self.curtainStatus = status
            return True
        except:
            return False

    def update(self):
        """Perde durumu ve ışık şiddetini oku"""
        try:
            if not self.serial_connection or not self.serial_connection.is_open:
                return
                
            self.serial_connection.reset_input_buffer()
            
            # Perde durumunu oku
            self.send_byte(0xA1) 
            status_byte = self.receive_byte()
            if status_byte is not None:
                self.curtainStatus = float(status_byte)
            
            time.sleep(0.02)

            # Işık şiddetini oku
            self.send_byte(0xA3)
            ldr_val = self.receive_byte()
            if ldr_val is not None:
                self.lightIntensity = float(ldr_val)

        except:
            pass

    def getCurtainStatus(self):
        return self.curtainStatus
    
    def getLightIntensity(self):
        return self.lightIntensity
    
    def getOutdoorTemp(self):
        return self.outdoorTemperature
    
    def getOutdoorPress(self):
        return self.outdoorPressure