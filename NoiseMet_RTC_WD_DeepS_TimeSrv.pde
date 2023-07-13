/*  
* SCPxx - Abril 2022
* 
* Codigo para realizar mediciones de ruido durante un tiempo especificado en minutos. Realizar
* promedio aritmetrico y logaritmico con las muestras disponibles. Lectura de temperatura,
* humedad y presion del sensor BME. Obtener hora de un servidor y establecerla como la hora del equipo.
* Enviar al equipo a deepsleep a una hora determinada. 
* 
*  Version:           1.6
*  Implementation:    Dario Espinoza S.
*  
*/

#include <WaspSensorCities_PRO.h>
#include <WaspFrame.h>
#include <Wasp4G.h>
#include <math.h>
#include <string.h>

/* Instancia de sensor BME temp, hum, pres
* Colocar sonda 9370-P en el Socket-E de P&S
*/
bmeCitiesSensor  bme(SOCKET_B);

/* Variables para almacenar temp, hum, pres*/
float temperature;
float humidity;
float pressure;
float leqdBa;

/* Variables para tiempo*/
unsigned long  epochNow;
unsigned long  epochMnt;
/* Tiempo en minutos para mediciones de ruido*/
int mntAvg = 1;

/* Tiempo de reinicio Wathcdog*/
int wdTime = 20;

/* Banderas para controlar procesamiento
* readBME: bandera para leer los datos BME (temp, hum, pres) y enviar los datos junto con noise
* doNoiseAvg: bandera para tomar muestras mientras se cumpla el tiempo de medicion
* checkTime: bandera para establecer el tiempo de medicion para tomar muestras de ruido
*/
boolean checkTime = true;
boolean doNoiseAvg = false;
boolean readBME = false;
boolean watchDog = false;

/* Banderas para visualizacion
* noiseView: visualizacion de datos de ruido en monitor serial
*/
boolean noiseView = false;

/* Variables para controlar envio usando 4G
* sendAtt: numero de intentos para realizar envios de informacion
* waitAtt: tiempo en segundos para esperar entre intentos de reenvios
*/
uint16_t sendAtt = 3;
uint16_t waitAtt = 10;

/* Variables para calcular promedio de muestras ruido*/
float sumdBlog = 0;
float sumdB = 0;
int cntdB = 0;

/* Identificador de nodo - EDITAR PARA CADA NODO */
// Waspmote identifier
char node_ID[] = "SCP01";
char node_Ubc[] = "Universidad del Azuay";

// Mobile operator paramenters
char apn[] = "m2m.movistar.ec";
char login[] = "";
char password[] = "";

// Debug flag, set to 1 if you want to see the complete process
#define debug_flag 0

// Server settings
char host[] = "127.0.0.1";
uint16_t port = 80;

// Time server settings
char timehost[] = "worldtimeapi.org";
uint16_t timeport = 80;
char resource[] = "/api/timezone/America/Guayaquil";

uint8_t error;
uint8_t error_init;


/* First configuration of the unit, it is only executed once
* Parameters: void
* Return: void
*/
void setup(){
  USB.ON(); 
  USB.println("************************************************");
  USB.println("*       Universidad del Azuay - IERSE          *");
  USB.println("* Medicion de Ruido y Variables Meteorologicas *");
  USB.println("************************************************");
  USB.println("Promedio logaritmico de ruido durante x minutos");
  USB.println("Lectura de BME temp, hum y pres");
  USB.println("Envio de datos via 4G");
  USB.println("Watchdog reinicio P&S, activa y desactiva en loop");
  USB.println("************************************************");
  // Show nodo information
  USB.println("________________________________________________");
  USB.printf("Nodo: %s \n", node_ID);
  USB.printf("Ubicacion: %s \n", node_Ubc);
  USB.printf("Intentos de envio: %d \n", sendAtt);
  USB.printf("Tiempo de espera reenvio: %d segundos\n", waitAtt);
  USB.printf("Watchdog time: %d minutos \n", wdTime);
  /*Configure the noise sensor for UART communication*/
  noise.configure();

  /*Powers RTC up, init I2C bus and read initial values*/
  RTC.ON();

  //0.1 Sets operator paramenters
  //_4G.set_APN(apn, login, password);

  //0.2 Show APN seetings
  //USB.println("APN Settings:");
  //_4G.show_APN();
  
  /*Setting time [yy:mm:dd:dow:hh:mm:ss]
   * 01 - domingo 
   * 02 - lunes
   * 03 - martes
   * 04 - miercoles
   * 05 - jueves
   * 06 - viernes
   * 07 - sabado
   * Unica vez para establecer hora en RTC
  */
  //RTC.setTime("21:06:07:02:21:36:00");

  //registerWaspmote();
  //setRTCDateTime();

  USB.println("________________________________________________");
}

/* Main loop
* Parameters: void
* Return: void
*/
void loop(){
  
  
  /*Importante para que transcurra el tiempo*/
  RTC.getTime();

  epochNow = RTC.getEpochTime((int)RTC.year, (int)RTC.month, (int)RTC.date, (int)RTC.hour, (int)RTC.minute, (int)RTC.second);

  /* Bandera para realizar el calculo desde NOW a mntAVG 
  * 
  */
  if(checkTime){
    USB.println("________________________________________________");
    USB.println("********* New Iteration Started ****************");
    
    // Establecer Watchdog para reiniciar en caso de que P&S se cuelgue
    RTC.setWatchdog(wdTime);
    USB.println(F(">- Watchdog settings:"));
    USB.println(RTC.getWatchdog());

    USB.println(F(">- Battery:"));

    // Show the remaining battery level
    USB.print(F("Battery Level: "));
    USB.print(PWR.getBatteryLevel(),DEC);
    USB.print(F(" %"));
    // Show the battery Volts
    USB.print(F(" | Battery (Volts): "));
    USB.printFloat(PWR.getBatteryVolts(),2);
    USB.println(F(" V"));

    USB.println(F(">- Noise measuring time:"));
    //USB.printf("Epoch Time from now: %lu \n", epochNow);
    USB.printf("Now: %s \n", RTC.getTime());
    epochMnt = addMinutesToNow(epochNow, mntAvg);

    /*Cambiar estado de banderas*/
    checkTime = false;
    doNoiseAvg = true;
    readBME =  false;
    watchDog =  false;

    USB.printf(">- Measuring noise (SLOW), %d minutes... \n", mntAvg);
    /*Configure the noise sensor for UART communication*/
    noise.configure();
    delay(500);
  }

  /* Calcular Noise Logaritmo*/
  if(doNoiseAvg){

    /* Medir ruido siempre que el tiempo actual (epochNow) sea menor que (epochMnt)*/
    if(epochNow <= epochMnt){
      measureNoise();
    }else{
      /*Cambiar estado de banderas*/
      checkTime = false;
      doNoiseAvg = false;
      readBME = true;
      watchDog =  false;
    }
    //delay(500);
  }

  /* Leer sensor BME, calcular promedio ruido, enviar datos*/
  if (readBME){
    /* Mostrar promedios ruido
    * Si el contador cntdB es mayor a cero, entonces se han realizado mediciones
    */
    USB.printf("Numero de muestras: %d \n", cntdB);

    /* Calculo de promedio logaritmico y promedio aritmetrico*/
    if (cntdB > 0){
      leqdBa = 10*log10(sumdBlog/cntdB);
      USB.printf("Promedio log ruido: ");
      USB.printFloat(leqdBa, 2);
      USB.println(" dB");
      
      float leqdBar = sumdB/cntdB;
      USB.print("Promedio ruido: ");
      USB.printFloat(leqdBar, 2);
      USB.println(" dB");
    }else{
      USB.println("There are no noise data, f**k :|");
      leqdBa = 0;
    }
    
    /* Sensor BME*/
    readSensorBME();

    /* Enviar datos via red GSM*/
    sendData();

    /* Pasar variables para siguiente proceso */
    sumdBlog = 0;
    sumdB = 0;
    cntdB = 0;
    checkTime = true;
    doNoiseAvg = false;
    readBME = false;
    watchDog =  true;

    delay(500);
  }

  /* Reinicar usando watchdog */
  if (watchDog){

    /* Desactivar watchdog, el proceso se termino correctamente
    * Watchdog se reinicia en siguiente iteracion
    */
    USB.println(">- Unsetting watchdog: ");
    RTC.unSetWatchdog();
    USB.println("Done!");
    USB.println("________________________________________________");

    /* Preparar y encerar variables para nueva iteracion*/ 
    checkTime = true;
    doNoiseAvg = false;
    readBME = false;
    watchDog =  false;

    delay(500);
  }
}



void registerWaspmote(){
    #if debug_flag != 0
    USB.println("[DEBUG] COMMUNICATION: Registering Waspmote");
  #endif
  _4G.set_APN(apn, login, password); 
  _4G.show_APN(); 
    #if debug_flag != 0
    USB.println("[DEBUG] COMMUNICATION: Switching on the 4G module");
  #endif
  error_init = _4G.ON();
}

void setRTCDateTime(){

  
  if (error_init == 0){

    USB.printf("[DEBUG] COMMUNICATION: Getting time from: %s", timehost);
    USB.println("");

    // send the request
    error = _4G.http( Wasp4G::HTTP_GET, timehost, timeport, resource);

    // Check the answer
    if (error == 0){
      USB.print("[INFO] COMMUNICATION: Succesful Clock request ");
      USB.println(_4G._httpCode);
      USB.print("[INFO] COMMUNICATION: Server response->");
      
      USB.println(_4G._buffer, _4G._length);

      // Pasar el contenido del buffer a una cadena
      char bufferResp[_4G._length];
      memcpy(bufferResp, &_4G._buffer[0], _4G._length);
      bufferResp[_4G._length] = '\0';

      char fechares[_4G._length] = "";
      getDateTime(bufferResp, fechares);
      USB.println(fechares);

      RTC.setTime(fechares);
    
    }else{
      USB.print(F("[ERROR] COMMUNICATION: error code: "));
      USB.println(error, DEC);
    }
  }else{
    // Problem with the communication with the 4G module
    USB.print(F("[ERROR] COMMUNICATION: 4G not started. error code: "));
    USB.println(error, DEC);
  }

  _4G.OFF();
}


/*
* Reemplazar caracter en una cadena
*/
void replaceChar (char string[], char repChar, char newChar){
  int slen = strlen(string);
  
  for(int i = 0; i < slen; i++){
    if(string[i] == repChar)
      string[i] = newChar;
  }
}

/*
* Obtener fecha y hora a partir de la cadena respuesta del servidor
*/
void getDateTime(char *myString, char *dateTimeStr){
  char *dtString = "\"datetime\"";
  char *dowString =  "\"day_of_week\"";

  boolean dtFlg = false;
  boolean dowFlg = false;

  char subsDat[9];
  char subsHor[9];
  char subsdow[2] = "0";

  char *tokens = strtok(myString, ",");
  
  while( tokens != NULL ) {

    char *dtPos = strstr(tokens, dtString);
    char *dowPos = strstr(tokens, dowString);

    if (dtPos != NULL){
      //USB.println(tokens);
      
      char *posT = strstr(tokens, "T");
      int dateposIni = (int)(posT - tokens) - 8;
      strncpy(subsDat, &tokens[dateposIni], 8);
      subsDat[8] = '\0';
      replaceChar(subsDat, '-', ':');
      //USB.println(subsDat);

      int horposIni = (int)(posT - tokens) + 1;
      strncpy(subsHor, &tokens[horposIni], 8);
      subsHor[8] = '\0';
      //USB.println(subsHor);

      dtFlg = true;
      free(posT);
    }

    if (dowPos != NULL){
      //USB.println(tokens);

      int dowposIni = strlen(tokens) - 1;
      char strtemp[2];
      strncpy(strtemp, &tokens[dowposIni], 1);
      strtemp[1] = '\0';

      int myInt = atoi(strtemp);
      myInt += 1;

      if (myInt > 7)
        myInt = 1;

      sprintf(strtemp, "%d", myInt);
      
      strcat(subsdow, strtemp);
      dowFlg = true;
    }
    
    tokens = strtok(NULL, ",");
  }

  /* 
   *  Si se han encontrado fecha y hora se retorna un string
   *  Setting time [yy:mm:dd:dow:hh:mm:ss]
   */
  if(dtFlg && dowFlg){
    strcat(dateTimeStr, subsDat);
    strcat(dateTimeStr, ":");
    strcat(dateTimeStr, subsdow);
    strcat(dateTimeStr, ":");
    strcat(dateTimeStr, subsHor);
    strcat(dateTimeStr, "");
    dateTimeStr[strlen(dateTimeStr)] = '\0';
  }else{
    dateTimeStr = "00:00:00:00:00:00:00";
    dateTimeStr[strlen(dateTimeStr)] = '\0';
  }
  
  //free(tokens);
  //free(dtString);
  //free(dowString);
}

/* Funcion para suma de valores de ruido
* Si el sensor no esta disponible, establece 
* el valor en cero
*/
void measureNoise(){
  /* Get a new measure of the SPLA from the noise sensor*/
  int status = noise.getSPLA(SLOW_MODE);
  float dBAnow;

  if (status == 0){
  
    // Suma aplicando logaritmos
    dBAnow = roundf(noise.SPLA*100)/100;
    
    delay(100);
    sumdBlog += pow(10, dBAnow/10); 
        
    /* Suma*/
    sumdB += dBAnow;

    /* Aumentar contador de mediciones*/
    cntdB++;

    if (noiseView){
      USB.printf("Muestra #%d ", cntdB);
      USB.printFloat(dBAnow, 2);
      USB.printf(" dbA \n");
    }
    
  }else{
    if (noiseView){
      USB.println(F("[CITIES PRO] Communication error. No response from the audio sensor (SLOW)"));    
    }
    /* Sumar cero si el sensor de ruido no esta disponible */
    sumdBlog += 0;
    sumdB += 0;
  }
}

/* Funcion para leer los valores de Temp, Hum y Pres
* Enciende el sensor BME y al finalizar la lectura lo apaga
*/
void readSensorBME(){
  USB.println(F(">- Reading BME..."));

  /*Encender sensor*/
  bme.ON();
  
  /*Leer valores temp, hum, pres*/
  temperature = bme.getTemperature();
  humidity = bme.getHumidity();
  pressure = bme.getPressure();

  /*And print the values via USB*/
  USB.printf("Temperatura: ");
  USB.printFloat(temperature, 2);
  USB.println(" C");
  USB.printf("Humedad: ");
  USB.printFloat(humidity, 2);
  USB.println(" %");
  USB.printf("Presion: ");
  USB.printFloat(pressure, 2);
  USB.println(" Pa");
  
  delay(500);

  /*Apagar sensor*/
  bme.OFF();
}

/* Funcion que retorna el tiempo actual en formato epoch
* y sumando los minutos especificados en la la variable
* global [mntAvg]
*/
unsigned long addMinutesToNow(unsigned long myEpoch, int minutes){

  /* Aumentar el tiempo de ahora mas minutos */
  unsigned long epochR = epochNow + 60 * minutes;
  timestamp_t   time;
  
  //USB.printf("Epoch Time from now plus %d minutes: %lu", minutes, epochR);

  // Break Epoch time into UTC time
  RTC.breakTimeAbsolute(epochR, &time); 
  USB.printf("Now plus %d minutes: %d/%d/%d %d:%d:%d\n", minutes, time.year, time.month, time.date, time.hour, time.minute, time.second);

  return epochR;
}

/* Send the data collected from the sensors using the 4G module
* Parameters: void
* Return: void
*/
void sendData(){

  /* Create frame */
  USB.println(F(">- Create frame..."));
  
  /* Set the Waspmote ID */
  frame.setID(node_ID);

  /* Create new frame (ASCII) */
  frame.createFrame(ASCII);

  /* Add Battery */
  frame.addSensor(SENSOR_BAT, PWR.getBatteryLevel());

  /* Add Board Sensors fields */
  frame.addSensor(SENSOR_CITIES_PRO_NOISE, leqdBa);
  frame.addSensor(SENSOR_CITIES_PRO_TC, temperature);
  frame.addSensor(SENSOR_CITIES_PRO_HUM, humidity);
  frame.addSensor(SENSOR_CITIES_PRO_PRES, pressure);
  
  /* Print frame */
  frame.showFrame();

  // 3.2 HTTP Request
  HTTPRequest();
}

/* Send the composed frame using HTTP Post method
* Parameters: void
* Return: void
*/
void HTTPRequest(){

  boolean tryAtt = true;
  uint16_t attNow = 0;
  
  USB.println(">- Sending data using 4G...");
  uint8_t error;
  
  /* Encender modulo 4G*/
  error = _4G.ON();
  
  /* Comprobar si se prende el modulo 4G */
  if (error == 0){
    
    /* Intentar por las veces especificadas en la variable global [sendAtt] */
    while(tryAtt){
      /* Send the request - HTTP POST */
      delay(500);
      error = _4G.sendFrameToMeshlium(host, port, frame.buffer, frame.length);
      
      /* Check the answer of HTTP POST */
      if(error == 0){
        /* Envio realizado, salir de loop*/
        USB.printf("Envio exitoso. HTTP code: ");
        USB.println(_4G._httpCode);
        USB.printf("Server response: ");
        USB.println(_4G._buffer, _4G._length);

        tryAtt = false;
        //break;
      }else{
        /* El envio no pudo ser realizado, proceso de reenvio
        * Apagar modulo 4G
        * Esperar segundos especificados en variable global [waitAtt]
        * Encender modulo 4G
        * Aumentar contador de intento de reenvios [tryAtt]
        */

        USB.printf("Fallo envio, reintentando en %d segundos. Error: %d \n", waitAtt, error);
        
        _4G.OFF();
        delay(1000*waitAtt);
        _4G.ON();
        attNow ++;

        /* Si se ha superado el numero de intentos de envio terminar bucle*/
        if(attNow >= sendAtt){
          tryAtt = false;
          //break;
          USB.println("Se ha superado el numero de intentos de envio :(");
          // Enviar a deepSleep
        }

        // If debug mode print error flag
        #if debug_flag != 0
          USB.print(F("[DEBUG] Sending error code: "));
          USB.println(error, DEC);
        #endif
      }
    }
  }else{
    USB.println("[CITIES PRO] Error switching ON the module");
    // If debug mode print error flag
    #if debug_flag != 0
      USB.print("[DEBUG] Turn-on error code: ");
      USB.println(error, DEC);
    #endif
  }

  /* Apagar modulo 4G*/
  _4G.OFF();
}
