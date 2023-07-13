﻿# NoiseMet.RTC.DeepSleep.NTP

Código para sensores remotos de medición de ruido, temperatura del aire, humedad relativa y presión barométrica.

Al encenderse el equipo se obtiene la hora y fecha proveniente de un servidor NTP para establecerla como la del sensor remoto. Posteriormente, se capturan mediciones de ruido en modo SLOW durante un tiempo especificado en minutos para obtener su promedio aritmétrico y logarítmico con las muestras obtenidas. Tras finalizar el periodo establecido para mediciones de ruido se realiza una lectura de temperatura, humedad y presion a través del sensor BME. Continuando con la ejecución, se envían los datos obtenidos por red celular usando comunicación M2M. Finalmente se pone el equipo en modo DEEPSLEEP a una hora determinada, durante 60 minutos, para luego iniciar este proceso nuevamente.
