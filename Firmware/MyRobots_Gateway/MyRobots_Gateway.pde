/***************************************************************
* Title: MyRobots Gateway
* Authors: RobotShop, based on ThingSpeak Original Sample Code
* Date: 19/05/2010
* Licence: GPL v3
* Description: Webserver and serial communication Gateway.
* URL: www.myrobots.com
*
* Description:
* Intended to be used with the MyRobots.com Beta Kit (i.e.
* Arduino + Ethernet Shield + Xbee). It also has provision for
* reading analogue sensors locally and remotely from otehr Xbee
* modules.
*
* This sketch allows to send information from a robot or a sensor
* to the Myrobots.com Server. The information can come wirelessly
* via Xbee or form local analogue sensors.
*
* This sketch requires the EasyTransfer Library available he:
* http://www.billporter.info/easytransfer-arduino-library/
* 
***************************************************************/

#include <SPI.h>
#include <Ethernet.h>
#include <EasyTransfer.h>

//Useful constants
#define max_robots 10 //Number of supported robots per geatway. It can be increase but care must be taken since it is easy to run out of memory.
#define max_feeds 8  //Number of feeds per robot.
#define update_interval 30000
#define max_fails 5
#define empty_key "0000000000000000"
#define robots_full 0xFF
#define key_len 16

//Communication
#define start_byte1 0xAA
#define start_byte2 0xEF
#define time_out 5
#define baud_rate 57600

// Local Network Settings

//See the paper lable on the Ethernet Shield for the MAC address
byte mac[]     = { 0x90, 0xA2, 0xDA, 0x00, 0x42, 0x60 }; // Must be unique on local network

byte ip[]      = { 192, 168,   1,  249 };                // Must be unique on local network
byte gateway[] = { 192, 168,   1,   1 };
byte subnet[]  = { 255, 255, 255,   0 };

// MyRobots.com Settings
byte server[]  = { 204, 92, 52, 252 };     // IP Address for the MyRobots API
Client client(server, 80);

// Robot data feeds
int robotData[max_robots][max_feeds];              //Reserved space for robots data feeds
String writeAPIKey[max_robots];            //Reserved space for robot API keys.
boolean dirty[max_robots];                 //If dirty is True, the robot info need to be sent to the server

// Variable Setup
long lastConnectionTime = 0; 
boolean lastConnected = false;
int resetCounter = 0;

//Analogue Sensors
int sensor[] = {A0, A1, A2, A3, A4, A5}; //Analogue sensor pins
String gatewayKey = "B2U9N3T4P16BE72F";
int gatewayIndex = robots_full;

//Create data structure for wireless transfer
EasyTransfer ET; 

struct RECEIVE_DATA_STRUCTURE
{
  int feeds[8];
  String key;
  int coordinates[2];
  String statusMessage;
};

RECEIVE_DATA_STRUCTURE remoteData;

void setup()
{
  //Setup Etehrnet
  Ethernet.begin(mac, ip, gateway, subnet);
  
  //Setup serial communication
  Serial.begin(baud_rate);
  
  ET.init(details(remoteData));
  
  //Initialize variables
   for (int i=0; i < max_robots; i++)
   {
     writeAPIKey[i] = empty_key;
     dirty[i] = false; 
     for (int n=0; n < max_feeds; n++)
       robotData[i][n]=0;
   }
  
  //Initiallize optional key for Gateway
  gatewayIndex = getIndex(gatewayKey);
  
  delay(1000); //Allow all initializations to finish
}

void loop()
{  char c;
  // Print Update Response to Serial Monitor
  if (client.available())
  {
    c = client.read();
    // Print the client response for debugging purposes
    //Serial.print(c);
  }
  
  // Disconnect from MyRobots.com
  if (!client.connected() && lastConnected)
  {
    Serial.println("\n...disconnected.\n");
    client.stop();
  }
  if(millis() - lastConnectionTime > update_interval)
  {
  // Update MyRobots.com
    for (int i=0; i < max_robots; i++)
    {
      if ((writeAPIKey[i] != empty_key) && dirty[i])
      {
        if(!client.connected() && (millis() - lastConnectionTime > update_interval))
        {
          updateServer(0);
          dirty[0] = false;
        }
      }
     }
 }
  if(ET.receiveData())
    syncData();
  updateLocalSensors(gatewayIndex);
  lastConnected = client.connected();
}

void updateServer(int index)
{
  int len = max_feeds*7 + (max_feeds-1);
  for (int j=0; j < max_feeds; j++)
    {len += String(robotData[index][j]).length();}
        
  if (client.connect())
  { 
    Serial.println("Connected to MyRobots.com...\n");
        
    client.print("POST /update HTTP/1.1\n");
    client.print("Host: bots.myrobots.com\n");
    client.print("Connection: close\n");
    client.print("X-THINGSPEAKAPIKEY: "+writeAPIKey[index]+"\n");
    client.print("Content-Type: application/x-www-form-urlencoded\n");
    client.print("Content-Length: ");
    client.print(len);
    client.print("\n\n");
    
    //Send the sensor data;
    for (int n=1; n < max_feeds; n++)
    {
      client.print("field");
      client.print(n);
      client.print("=");
      client.print(robotData[index][n-1]);
      client.print("&");
    }

    client.print("field");
    client.print(max_feeds);
    client.print("=");
    client.print(robotData[index][max_feeds-1]);
    
    lastConnectionTime = millis();
    resetCounter = 0;
  }
  else
  {
    Serial.println("Connection Failed.\n");   
    
    resetCounter++;
    if (resetCounter >= max_fails ) {resetEthernetShield();}

    lastConnectionTime = millis(); 
  }
}

void updateData(int robotIndex, int data[8])
{
  int robotData[robotIndex][8];
  dirty[robotIndex] = true;
}

int getIndex(String key)
// Returns the index of where to store the robot data.
{
  for (int i=0; i < max_robots; i++)
  {
    if (writeAPIKey[i] == key) return i;
  }
  
  for (int i=0; i < max_robots; i++)
  {
    if (writeAPIKey[i] == empty_key)
    {
      writeAPIKey[i] = key;
      return i;
    }
  }
  Serial.print("Robots Full!");
  delay(10);
  return robots_full;
}

void clearIndex(int index)
// Clears given index and makes it available for a new robot.
{
  if (index < max_robots && index >= 0)
    writeAPIKey[index] = empty_key;
}

void resetEthernetShield()
{
  Serial.println("Resetting Ethernet Shield.\n"); 
  
  client.stop();
  delay(1000);
  
  Ethernet.begin(mac, ip, gateway, subnet);
  delay(1000);
}

//Only enable if a valid key is provided at "index"
void updateLocalSensors(int index)
{
  dirty[index] = true;
  for (int i=0; i < 6; i++)
  {
    robotData[index][i] = analogRead(sensor[i]);
  }
}

void syncData()
{
  int index = getIndex(remoteData.key);
  if (index != robots_full)
  {
    for (int i=0; i < max_feeds; i++)
      robotData[index][i] = remoteData.feeds[i];
    dirty[index]= true;
  }
}

