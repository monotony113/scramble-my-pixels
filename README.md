###  A macOS application that scrambles pixels (literally) 

This app takes an image and a password and "scrambles" (ciphers) the image's bitmap, returning an image that can still be opened normally but completely unrecognizable. (Because it only moves pixels around, ciphering an image with only 1 color produces the same image)

Given a scrambled image and the password used to scramble it, the app can "unscramble" (decipher) the image back to its original appearance. 

This app uses SHA-512 as its basis for the algorithm it uses to scramble the image according to the specified password, thus the likelihood that two passwords can be used to decipher the same image is related two the likelihood of a collision attack (minus some 60 orders of magnitude[1]). As always, choose a long, difficult password -- if you choose "1234" as your password, it's _very_ easy to brute-force attack your image.

This application is written as a fun experiment i.e. full of bugs. It has not been tested extensively. Usage of this in a productive environment is not recommended. Use at your own discretion. The creator of the application cannot be held liable for any damage of any kind that may arise from said application.

This is the first time I write in Swift, or any strong-typed language. Before this, 90% of the time I was programming was spent staring at "undefined has no property 'length'", this time 90% of the time was spent on type matching.

Input image format is any _bitmap_ image readable by CGImage, including JPEG, PNG, TIFF, RAW images, and HEIC. Accepts 8-, 16-, and 32-bit integer or floating-point images (some functionalities may not be available on floating-point images). Output format is either PNG or TIFF depending on input. Does not work with vector graphs. 

Requires macOS 10.13 and a Metal-compatible GPU.

---

[1] The output range of the SHA-512 hash function is 2^512 = 1.340781E+154. However, the algorithm in the app does not use the information in the digest fully but only utilizes the ordering of bytes i.e. how each bytes compares to each other. According to my back-of-the-envelop math this output range of the password function in the app should be 64-permutation of 64 [P(64, 64)], which Google says is 1.268869321E+89.
