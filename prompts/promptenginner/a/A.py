import os
import sys
import json
import requests
from pathlib import Path


def get_user_input():
    """Get the original prompt from the user."""
    print("Welcome to the Prompt Optimizer!")
    print("Enter your prompt below:")
    print("(Press Enter on an empty line to finish input)")

    lines = []

    while True:
        try:
            line = input()
            if line.strip() == "":
                # Empty line means end of input
                break
            lines.append(line)
        except EOFError:
            break

    return "\n".join(lines).strip()


def load_credentials(creds_path):
    """Load the OAuth credentials from file."""
    try:
        with open(creds_path, 'r', encoding='utf-8') as f:
            creds_data = f.read().strip()
            # Try parsing as JSON, if not JSON then treat as raw credential data
            try:
                return json.loads(creds_data)
            except json.JSONDecodeError:
                # If it's not JSON, return as raw string
                return creds_data
    except FileNotFoundError:
        print(f"Credentials file not found: {creds_path}")
        return None
    except Exception as e:
        print(f"Error reading credentials file: {str(e)}")
        return None


def apply_prompt_engineering_techniques(user_prompt):
    """
    Apply advanced prompt engineering techniques to maximize effectiveness.
    """
    # Construct a comprehensive prompt engineering template
    engineering_template = f"""You are an expert in prompt engineering and optimization. Your task is to enhance the following user prompt to maximize its effectiveness for achieving the intended goals with any AI system.

ORIGINAL PROMPT:
{user_prompt}

OPTIMIZED PROMPT REQUIREMENTS:
1. CLARITY: Make the objective crystal clear and unambiguous
2. SPECIFICITY: Include specific details, constraints, and requirements
3. STRUCTURE: Organize with clear sections, steps, or bullet points if needed
4. TONE: Match the appropriate tone for the task (professional, creative, analytical, etc.)
5. COMPLETENESS: Ensure all necessary context is included
6. ACTIONABILITY: Provide clear instructions on what output is expected
7. CONSTRAINTS: Define any limitations, requirements, or boundaries
8. FORMAT: Specify desired output format if relevant (list, paragraph, JSON, etc.)
9. EXAMPLES: Include relevant examples if they would aid understanding
10. FEW-SHOT: If appropriate, provide examples of desired input/output

Return ONLY the optimized prompt without any additional commentary.
"""
    return engineering_template


def call_qwen_api(prompt, credentials):
    """
    Call the Qwen Code AI API with the given prompt and credentials.
    """
    # Extract the access token from the credentials
    if isinstance(credentials, dict):
        access_token = credentials.get('access_token', '')
        resource_url = credentials.get('resource_url', 'portal.qwen.ai')
        expiry_date = credentials.get('expiry_date', 0)
    else:
        print("Credentials format is not a dictionary. Exiting.")
        return None

    # Check if token has expired (compare with current timestamp)
    import time
    current_time_ms = int(time.time() * 1000)
    if expiry_date < current_time_ms:
        print("Warning: Access token may have expired. Response might fail.")

    # Construct the API endpoint URL based on the resource_url
    api_base_url = f"https://{resource_url}"

    # The current endpoint we know works (based on your test) is /v1/chat/completions
    # Based on your recent discovery, the supported models are 'coder-model' and 'vision-model'
    possible_endpoints = [
        f"{api_base_url}/v1/chat/completions",     # Based on your error response, this is the right endpoint
    ]

    # Prepare headers for the API request
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    # Now that we know the actual supported models, let's try with those specific names
    # Since this is a "Prompt Optimizer", the 'coder-model' would be most appropriate
    model_names = ["coder-model", "vision-model"]

    payloads_to_try = []

    # Create payloads with the actual supported model names
    for model in model_names:
        payloads_to_try.append({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 1000,
            "temperature": 0.7
        })

        # Also try with system message for better prompt engineering
        payloads_to_try.append({
            "model": model,
            "messages": [
                {"role": "system", "content": "You are an expert in prompt engineering and optimization. Your task is to enhance the following user prompt to maximize its effectiveness for achieving the intended goals with any AI system."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": 1000,
            "temperature": 0.7
        })

    # Try different payloads with the actual supported models
    for endpoint in possible_endpoints:
        for payload in payloads_to_try:
            try:
                model_name = payload.get('model', 'N/A (not specified)')
                print(f"Trying API endpoint: {endpoint} with model: {model_name}")
                response = requests.post(endpoint, headers=headers, json=payload, timeout=60)

                # Check if the request was successful
                if response.status_code in [200, 201]:
                    response_data = response.json()

                    # Check if there's an error in the response
                    if 'error' in response_data:
                        error_msg = response_data['error'].get('message', 'Unknown error')
                        print(f"API returned error: {error_msg}")
                        # If it's a model not supported error, try next payload
                        if "not supported" in error_msg or "invalid" in error_msg:
                            print(f"Model issue encountered, trying next payload...")
                            continue
                        else:
                            # For other errors, continue with next attempt
                            print("Other error encountered, trying next payload...")
                            continue

                    # Try different ways to extract the response text
                    text_result = None

                    # Method 1: Chat completion style (most likely based on the error response)
                    if 'choices' in response_data:
                        text_result = response_data.get('choices', [{}])[0].get('message', {}).get('content', '')

                        # If content is still empty, try getting 'text' from choice
                        if not text_result:
                            text_result = response_data.get('choices', [{}])[0].get('text', '')

                    # Method 2: Standard OpenAI-style response
                    if not text_result and 'choices' in response_data:
                        text_result = response_data.get('choices', [{}])[0].get('text', None)

                    # Method 3: Alternative response formats
                    if not text_result and 'response' in response_data:
                        text_result = response_data.get('response', '')

                    # Method 4: Direct text response
                    if not text_result and 'text' in response_data:
                        text_result = response_data.get('text', '')

                    # Method 5: Simple output field
                    if not text_result and 'output' in response_data:
                        text_result = response_data.get('output', '')

                    if text_result:
                        print("Successfully retrieved response from Qwen API")
                        return text_result
                    else:
                        print(f"No text found in response from {endpoint}")
                        continue

                else:
                    # Print error details if available
                    try:
                        error_response = response.json()
                        print(f"API request failed with status {response.status_code}: {error_response}")
                    except:
                        print(f"API request failed with status code: {response.status_code}")
                        print(f"Response: {response.text}")
                    continue  # Try next endpoint/payload combination

            except requests.exceptions.Timeout:
                print(f"Request timed out for endpoint: {endpoint}")
                continue
            except requests.exceptions.RequestException as e:
                print(f"Error making API request to {endpoint}: {str(e)}")
                continue
            except ValueError:  # Includes json.JSONDecodeError in Python 3.5+
                print(f"Invalid JSON response from {endpoint}")
                continue
            except Exception as e:
                print(f"Unexpected error during API call to {endpoint}: {str(e)}")
                continue

    print("All API attempts failed. Could not connect to Qwen API.")
    return None


def get_qwen_config_dir():
    """Get the Qwen configuration directory, with fallback options."""
    # Common locations for Qwen configuration
    possible_paths = [
        "C:\\Users\\micha\\.qwen\\",  # Current user's config
        os.path.expanduser("~\\.qwen\\"),  # User home directory
        os.path.join(os.environ.get("APPDATA", ""), "qwen\\"),  # Windows app data
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "qwen\\"),  # Windows local app data
    ]

    for path in possible_paths:
        if path and os.path.exists(path):
            return path

    return None


def load_settings(settings_path):
    """Load Qwen settings from file."""
    try:
        with open(settings_path, 'r', encoding='utf-8') as f:
            settings_data = f.read().strip()
            return json.loads(settings_data)
    except FileNotFoundError:
        print(f"Settings file not found: {settings_path}")
        return {}
    except json.JSONDecodeError as e:
        print(f"Error parsing settings file: {str(e)}")
        return {}
    except Exception as e:
        print(f"Error reading settings file: {str(e)}")
        return {}


def main():
    """Main application entry point."""
    print("Starting Prompt Optimizer...")

    # Find the Qwen configuration directory
    config_dir = get_qwen_config_dir()
    if not config_dir:
        print("Could not locate Qwen configuration directory. Exiting.")
        sys.exit(1)

    print(f"Using Qwen configuration directory: {config_dir}")

    # Load settings from settings.json
    settings_path = os.path.join(config_dir, "settings.json")
    settings = load_settings(settings_path)
    print("Settings loaded successfully.")

    # Load credentials
    creds_path = os.path.join(config_dir, "oauth_creds.json")
    credentials = load_credentials(creds_path)

    if not credentials:
        print("Could not load credentials. Exiting.")
        sys.exit(1)

    print("Credentials loaded successfully.")

    # Get user input
    user_prompt = get_user_input()

    if not user_prompt:
        print("No prompt provided. Exiting.")
        sys.exit(1)

    print("\nOriginal prompt received:")
    print("-" * 50)
    print(user_prompt)
    print("-" * 50)

    # Apply prompt engineering techniques to optimize the prompt
    optimized_prompt_template = apply_prompt_engineering_techniques(user_prompt)

    print("\nSending optimized prompt template to Qwen API...")

    # Call the Qwen API
    try:
        api_response = call_qwen_api(optimized_prompt_template, credentials)

        if api_response is not None:
            print("\nReceived optimized prompt from Qwen Code AI:")
            print("=" * 50)
            print(api_response)
            print("=" * 50)

            # Optionally save to a file
            save_option = input("\nWould you like to save the optimized prompt to a file? (y/n): ")
            if save_option.lower() in ['y', 'yes']:
                filename = input("Enter filename to save to (default: optimized_prompt.txt): ") or "optimized_prompt.txt"
                with open(filename, 'w', encoding='utf-8') as f:
                    f.write(api_response)
                print(f"Optimized prompt saved to {filename}")
        else:
            print("Failed to get response from Qwen API. Exiting.")
            sys.exit(1)

    except Exception as e:
        print(f"Error communicating with Qwen API: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
