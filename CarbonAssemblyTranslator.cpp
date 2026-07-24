#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <bitset>
#include "json.hpp"

using json = nlohmann::json;

std::vector<std::string> readFile (std::string input) {
    std::ifstream file(input);
    // open file

    if (!file.is_open()) {
        std::cout << "Error could not open file" << std::endl;
        return { "Error" };
    }

    std::string line;
    std::vector<std::string> contents;
    //read file
     while (std::getline(file, line)) {
        contents.push_back(line);
    }

    file.close();
    return contents;
    //close file
}

std::vector<std::string> writeFile (std::string inputFile,std::vector<std::string> input) {
    std::ofstream file(inputFile, std::ios::trunc);
    //open file

    if (!file.is_open()) {
        std::cout << "Error could not open file" ;
        std::cout << inputFile << std::endl;

        return { "Error" };
    }

    for (const auto& i: input){
        file << i << "\n"; 
    }
    return { "Worked" };
}

json readJson (std::string input) {
    
    std::ifstream file(input);
    //open the json

    if(!file.is_open()) {
        std::cout << "Error could not open json" << std::endl;
        return json::object();
    }

    json data;
    file >> data;
    file.close();
    //store data and close file

    return data;
    //output all the data
}

bool isInteger(std::string_view inputString) {
    if (inputString.empty()) return false;

    int value = 0;

    auto [ptr, ec] = std::from_chars(inputString.data(), inputString.data() + inputString.size(), value);

    return ec == std::errc{} && ptr == inputString.data() + inputString.size();
}

std::vector<std::string> split(std::string inputString) {
    std::stringstream ss(inputString);

    std::string word;
    std::vector<std::string> tokens;

    while (ss >> word) {
        tokens.push_back(word);
    }

    return tokens;
}

int main(){

    json config = readJson("D:/programs/CarbonAssemblyTranslator/config.json");

    const std::string inputFile = config["inputFile"];
    const std::string binaryFile = config["binaryFile"];
    const std::string outputFile = config["outputFile"];
    //get settings from the config

    std::vector<std::string> input = readFile(inputFile);//get the program from the input file

    if (!input.empty() && input[0] == "Error") {
        std::cout << "input has no data" << std::endl;
        return 1;
    }

    json binary = readJson(binaryFile);
    std::vector<std::string> output;
    for (const auto& i : input) {
        
        std::vector<std::string> tokens = split(i);
        std::string instruction = tokens[0];

        if (binary.contains(instruction)) {
            std::string binaryLine = binary[instruction];//translate asm
            output.push_back(binaryLine);

            if (instruction == "LDC") {
                if (tokens.size() >= 2 && isInteger(tokens[1])) { // if a load instruction is recieved and a valid constant is present
                    output.push_back(std::bitset<16>{std::stoi(tokens[1])}.to_string() + " // A Signed Integer");
                }   else {
                    std::cout << "Error. No valid constant. ";
                    std::cout << ":(" << std::endl;
                    output = {"Error. No valid constant."};//not return so you can see the problem in the output txt
                    break;
                } 
            } 
        }

        if (i.empty()){//if a line is empty, ignore it
            output.push_back("");

        } else if (i.rfind("//", 0) == 0){//preserve comments
            output.push_back(i);

        }  else {
            std::cout << "Error. Token not supported: ";
            std::cout << i << std::endl;
            output = {"Error. Token not supported:",i};
        }

    }

    writeFile(outputFile,output);
    std::cout << "Finshed Translation" << std::endl;
    return 0;
}
