# GUI kütüphaneleri ve API modulu
import customtkinter as ctk
import api
import threading
import time

# Aydınlık tema ve mavi renk şeması
ctk.set_appearance_mode("Light") 
ctk.set_default_color_theme("blue")

# Ana uygulama sınıfı
class HomeAutomationApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("Akıllı Ev Otomasyonu - EEE/CmpE")
        self.geometry("900x750")
        self.minsize(800, 600)
        self.running = True
        self.lock = threading.Lock()  # Thread güvenliği için

        # Sistem bağlantılarını oluştur
        self.ac_system = api.AirConditionerSystemConnection()
        self.ac_system.setComPort("COM18")  # Klima portu
        
        self.curtain_system = api.CurtainControlSystemConnection()
        self.curtain_system.setComPort("COM14")  # Perde portu

        # Sayfa konteynerı oluştur
        self.container = ctk.CTkFrame(self)
        self.container.pack(fill="both", expand=True)
        
        self.container.grid_rowconfigure(0, weight=1)
        self.container.grid_columnconfigure(0, weight=1)

        # Tüm sayfaları oluştur
        self.frames = {}
        
        for F in (MainMenuPage, AirConditionerPage, CurtainControlPage):
            page_name = F.__name__
            frame = F(parent=self.container, controller=self)
            self.frames[page_name] = frame
            frame.grid(row=0, column=0, sticky="nsew")

        self.show_frame("MainMenuPage")

        # Arka plan thread'i başlat
        self.thread = threading.Thread(target=self.backend_worker, daemon=True)
        self.thread.start()
        
        self.update_gui_loop()

    def show_frame(self, page_name):
        frame = self.frames[page_name]
        frame.tkraise()

    def backend_worker(self):
        """Arka planda sürekli veri güncelle"""
        while self.running:
            try:
                # Klima sistemini güncelle
                if self.ac_system.serial_connection and self.ac_system.serial_connection.is_open:
                    with self.lock:
                        self.ac_system.update()
                
                time.sleep(5)  # 5 saniyede bir
                
                # Perde sistemini güncelle
                if self.curtain_system.serial_connection and self.curtain_system.serial_connection.is_open:
                    with self.lock:
                        self.curtain_system.update()
                        
                time.sleep(0.5)
                
            except Exception as e:
                print(f"[BACKEND] Hata: {e}")
                time.sleep(1)

    def update_gui_loop(self):
        """GUI elemanlarını güncelle"""
        try:
            with self.lock:
                ac_page = self.frames["AirConditionerPage"]
                
                # Hedef sıcaklığı göster
                desired = self.ac_system.getDesiredTemp()
                ac_page.lbl_des.configure(text=f"{desired} °C")
                
                # Board otonom çalışıyor, değerler board'da
                ac_page.lbl_amb.configure(text="Board'da")
                ac_page.lbl_fan.configure(text="Board'da")
                
                # Bağlantı durumu
                if self.ac_system.serial_connection and self.ac_system.serial_connection.is_open:
                    ac_page.lbl_conn.configure(
                        text=f"Bağlantı: {self.ac_system.comPort} (Aktif)",
                        text_color="#27AE60"
                    )
                else:
                    ac_page.lbl_conn.configure(
                        text="Bağlantı: Kapalı",
                        text_color="#C0392B"
                    )

                # Perde sistemi bilgilerini güncelle
                cur_page = self.frames["CurtainControlPage"]
                cur_page.lbl_stat.configure(text=f"%{self.curtain_system.getCurtainStatus()}")
                cur_page.lbl_light.configure(text=f"{self.curtain_system.getLightIntensity()} Lux")
                
                if self.curtain_system.serial_connection and self.curtain_system.serial_connection.is_open:
                    cur_page.lbl_conn.configure(
                        text=f"Bağlantı: {self.curtain_system.comPort} (Aktif)",
                        text_color="#27AE60"
                    )
                else:
                    cur_page.lbl_conn.configure(
                        text="Bağlantı: Kapalı",
                        text_color="#C0392B"
                    )
        except Exception as e:
            print(f"[GUI] Güncelleme hatası: {e}")
        
        self.after(2000, self.update_gui_loop)

    def on_closing(self):
        print("[APP] Uygulama kapatılıyor...")
        self.running = False
        time.sleep(0.5) 
        
        try:
            if self.ac_system.serial_connection:
                self.ac_system.close()
            if self.curtain_system.serial_connection:
                self.curtain_system.close()
        except:
            pass
        
        self.destroy()


# ANA MENÜ
class MainMenuPage(ctk.CTkFrame):
    def __init__(self, parent, controller):
        super().__init__(parent, fg_color="#E3E8EC") 
        
        center_frame = ctk.CTkFrame(self, fg_color="white", corner_radius=25, border_width=1, border_color="#CBD5E0", width=450)
        center_frame.place(relx=0.5, rely=0.5, anchor="center")
        
        content_frame = ctk.CTkFrame(center_frame, fg_color="transparent")
        content_frame.pack(padx=50, pady=50)

        welcome_label = ctk.CTkLabel(content_frame, text="Hoş Geldiniz", font=("Segoe UI", 16), text_color="#718096")
        welcome_label.pack(pady=(0, 5))

        label = ctk.CTkLabel(content_frame, text="AKILLI EV", font=("Segoe UI", 36, "bold"), text_color="#1A202C")
        label.pack(pady=(0, 0))
        
        sub_label = ctk.CTkLabel(content_frame, text="OTOMASYON SİSTEMİ", font=("Segoe UI", 14, "bold"), text_color="#4A5568")
        sub_label.pack(pady=(0, 40))

        btn1 = ctk.CTkButton(content_frame, text="❄  KLİMA SİSTEMİ", width=300, height=60, 
                             font=("Segoe UI", 16, "bold"), 
                             corner_radius=30,
                             fg_color="#3B82F6", hover_color="#2563EB",
                             command=lambda: [controller.ac_system.open(), controller.show_frame("AirConditionerPage")])
        btn1.pack(pady=10)

        btn2 = ctk.CTkButton(content_frame, text="🪟  PERDE KONTROL", width=300, height=60, 
                             font=("Segoe UI", 16, "bold"), 
                             corner_radius=30,
                             fg_color="#3B82F6", hover_color="#2563EB",
                             command=lambda: [controller.curtain_system.open(), controller.show_frame("CurtainControlPage")])
        btn2.pack(pady=10)

        ctk.CTkFrame(content_frame, height=2, fg_color="#EDF2F7", width=200).pack(pady=20)

        btn3 = ctk.CTkButton(content_frame, text="ÇIKIŞ YAP", width=300, height=60, 
                             font=("Segoe UI", 16, "bold"), 
                             corner_radius=30,
                             fg_color="#EF4444", hover_color="#DC2626",
                             command=controller.on_closing)
        btn3.pack(pady=(0, 0))
        
        version_label = ctk.CTkLabel(content_frame, text="v1.2 • System Online", font=("Segoe UI", 10), text_color="#A0AEC0")
        version_label.pack(pady=(15, 0))


def create_info_row(parent, title, unit):
    frame = ctk.CTkFrame(parent, fg_color="transparent")
    frame.pack(fill="x", pady=8, padx=10)
    
    dot = ctk.CTkLabel(frame, text="●", font=("Arial", 12), text_color="#BDC3C7")
    dot.pack(side="left", padx=(0, 10))

    lbl_title = ctk.CTkLabel(frame, text=title, font=("Segoe UI", 16, "bold"), text_color="#555555", width=200, anchor="w")
    lbl_title.pack(side="left")
    
    lbl_value = ctk.CTkLabel(frame, text=f"-- {unit}", font=("Segoe UI", 16), text_color="#2980B9", anchor="e")
    lbl_value.pack(side="right", padx=10)
    
    separator = ctk.CTkFrame(parent, height=2, fg_color="#EEEEEE")
    separator.pack(fill="x", padx=10, pady=2)
    
    return lbl_value


# KLİMA SAYFASI
class AirConditionerPage(ctk.CTkFrame):
    def __init__(self, parent, controller):
        super().__init__(parent, fg_color="#E3E8EC")
        self.controller = controller

        main_box = ctk.CTkFrame(self, width=600, fg_color="white", corner_radius=20)
        main_box.place(relx=0.5, rely=0.5, anchor="center", relwidth=0.9, relheight=0.9)
        
        inner_frame = ctk.CTkFrame(main_box, fg_color="transparent")
        inner_frame.pack(fill="both", expand=True, padx=40, pady=40)

        header_frame = ctk.CTkFrame(inner_frame, fg_color="transparent")
        header_frame.pack(fill="x", pady=(0, 20))
        
        ctk.CTkLabel(header_frame, text="KLİMA KONTROLÜ", font=("Segoe UI", 28, "bold"), text_color="#2C3E50").pack(side="left")
        
        self.lbl_conn = ctk.CTkLabel(header_frame, text="Bağlantı: Bekleniyor...", text_color="#95A5A6", font=("Segoe UI", 12))
        self.lbl_conn.pack(side="right", anchor="e")

        info_frame = ctk.CTkFrame(inner_frame, fg_color="#FBFCFC", corner_radius=15, border_width=1, border_color="#E0E0E0")
        info_frame.pack(pady=10, fill="x")
        
        info_content = ctk.CTkFrame(info_frame, fg_color="transparent")
        info_content.pack(padx=20, pady=15, fill="x")

        self.lbl_amb = create_info_row(info_content, "Ortam Sıcaklığı:", "°C")
        self.lbl_des = create_info_row(info_content, "Hedef Sıcaklık:", "°C")
        self.lbl_fan = create_info_row(info_content, "Fan Hızı:", "RPS")

        action_frame = ctk.CTkFrame(inner_frame, fg_color="transparent")
        action_frame.pack(pady=30, fill="x")

        ctk.CTkLabel(action_frame, text="YENİ DEĞER GİRİŞİ", font=("Segoe UI", 14, "bold"), text_color="#7F8C8D").pack(anchor="w", pady=(0, 10))
        
        input_row = ctk.CTkFrame(action_frame, fg_color="transparent")
        input_row.pack(fill="x")
        
        self.entry = ctk.CTkEntry(input_row, placeholder_text="Örn: 24.5", height=50, 
                                  font=("Segoe UI", 18), 
                                  corner_radius=10, border_color="#BDC3C7", fg_color="#FDFFE6") 
        self.entry.pack(side="left", fill="x", expand=True, padx=(0, 15))
        self.entry.bind('<Return>', lambda event: self.send_data())

        self.btn_set = ctk.CTkButton(input_row, text="DEĞERİ GÖNDER", width=160, height=50, 
                                     font=("Segoe UI", 14, "bold"), 
                                     corner_radius=10,
                                     fg_color="#27AE60", hover_color="#2ECC71", 
                                     command=self.send_data)
        self.btn_set.pack(side="right")

        self.lbl_msg = ctk.CTkLabel(action_frame, text="", font=("Segoe UI", 12, "bold"))
        self.lbl_msg.pack(pady=(10, 0), anchor="w")

        self.btn_back = ctk.CTkButton(inner_frame, text="GERİ DÖN", height=45, 
                                      fg_color="#95A5A6", hover_color="#7F8C8D",
                                      corner_radius=10, font=("Segoe UI", 14, "bold"),
                                      command=lambda: [controller.show_frame("MainMenuPage"), controller.ac_system.close(), self.clear_msg()])
        self.btn_back.pack(side="bottom", fill="x", pady=0) 

    def send_data(self):
        try:
            val = float(self.entry.get())
            if val < 10 or val > 50:
                self.lbl_msg.configure(text="HATA: Sıcaklık 10-50°C arasında olmalı!", text_color="#C0392B")
                return
            
            def send_thread():
                with self.controller.lock:
                    success = self.controller.ac_system.setDesiredTemp(val)
                    if success:
                        self.after(0, lambda: self.lbl_msg.configure(
                            text=f"BAŞARILI: {val}°C gönderildi.", 
                            text_color="#27AE60"
                        ))
                    else:
                        self.after(0, lambda: self.lbl_msg.configure(
                            text="HATA: Gönderim başarısız!", 
                            text_color="#C0392B"
                        ))
            
            threading.Thread(target=send_thread, daemon=True).start()
            self.entry.delete(0, 'end')
            
        except ValueError:
            self.lbl_msg.configure(text="HATA: Lütfen geçerli bir sayı girin!", text_color="#C0392B")

    def clear_msg(self):
        self.lbl_msg.configure(text="")
        self.entry.delete(0, 'end')


# PERDE SAYFASI
class CurtainControlPage(ctk.CTkFrame):
    def __init__(self, parent, controller):
        super().__init__(parent, fg_color="#E3E8EC")
        self.controller = controller

        main_box = ctk.CTkFrame(self, width=600, fg_color="white", corner_radius=20)
        main_box.place(relx=0.5, rely=0.5, anchor="center", relwidth=0.9, relheight=0.9)
        
        inner_frame = ctk.CTkFrame(main_box, fg_color="transparent")
        inner_frame.pack(fill="both", expand=True, padx=40, pady=40)

        header_frame = ctk.CTkFrame(inner_frame, fg_color="transparent")
        header_frame.pack(fill="x", pady=(0, 20))
        
        ctk.CTkLabel(header_frame, text="PERDE KONTROLÜ", font=("Segoe UI", 28, "bold"), text_color="#2C3E50").pack(side="left")

        self.lbl_conn = ctk.CTkLabel(header_frame, text="Bağlantı: Bekleniyor...", text_color="#95A5A6", font=("Segoe UI", 12))
        self.lbl_conn.pack(side="right", anchor="e")

        info_frame = ctk.CTkFrame(inner_frame, fg_color="#FBFCFC", corner_radius=15, border_width=1, border_color="#E0E0E0")
        info_frame.pack(pady=10, fill="x")
        
        info_content = ctk.CTkFrame(info_frame, fg_color="transparent")
        info_content.pack(padx=20, pady=15, fill="x")

        self.lbl_stat = create_info_row(info_content, "Perde Kapalılık Durumu:", "%")
        self.lbl_light = create_info_row(info_content, "Işık Şiddeti:", "Lux")
        
        action_frame = ctk.CTkFrame(inner_frame, fg_color="transparent")
        action_frame.pack(pady=30, fill="x")

        ctk.CTkLabel(action_frame, text="YENİ PERDE DURUMU (%)", font=("Segoe UI", 14, "bold"), text_color="#7F8C8D").pack(anchor="w", pady=(0, 10))
        
        input_row = ctk.CTkFrame(action_frame, fg_color="transparent")
        input_row.pack(fill="x")
        
        self.entry = ctk.CTkEntry(input_row, placeholder_text="Örn: 50", height=50, 
                                  font=("Segoe UI", 18),
                                  corner_radius=10, border_color="#BDC3C7", fg_color="#FDFFE6")
        self.entry.pack(side="left", fill="x", expand=True, padx=(0, 15))
        self.entry.bind('<Return>', lambda event: self.send_data())

        self.btn_set = ctk.CTkButton(input_row, text="AYARI GÖNDER", width=160, height=50, 
                                     font=("Segoe UI", 14, "bold"), 
                                     corner_radius=10,
                                     fg_color="#27AE60", hover_color="#2ECC71", 
                                     command=self.send_data)
        self.btn_set.pack(side="right")

        self.lbl_msg = ctk.CTkLabel(action_frame, text="", font=("Segoe UI", 12, "bold"))
        self.lbl_msg.pack(pady=(10, 0), anchor="w")

        self.btn_back = ctk.CTkButton(inner_frame, text="GERİ DÖN", height=45, 
                                      fg_color="#95A5A6", hover_color="#7F8C8D",
                                      corner_radius=10, font=("Segoe UI", 14, "bold"),
                                      command=lambda: [controller.show_frame("MainMenuPage"), controller.curtain_system.close(), self.clear_msg()])
        self.btn_back.pack(side="bottom", fill="x", pady=0)

    def send_data(self):
        try:
            val = float(self.entry.get())
            if val < 0 or val > 100:
                self.lbl_msg.configure(text="HATA: Değer %0 - %100 arasında olmalı!", text_color="#C0392B")
                return

            threading.Thread(target=lambda: self.controller.curtain_system.setCurtainStatus(val), daemon=True).start()
            self.lbl_msg.configure(text=f"BAŞARILI: Perde %{int(val)} ayarlandı.", text_color="#27AE60")
            self.entry.delete(0, 'end')
        except ValueError:
            self.lbl_msg.configure(text="HATA: Lütfen sayısal bir değer girin!", text_color="#C0392B")

    def clear_msg(self):
        self.lbl_msg.configure(text="")
        self.entry.delete(0, 'end')


if __name__ == "__main__":
    app = HomeAutomationApp()
    app.protocol("WM_DELETE_WINDOW", app.on_closing)
    app.mainloop()